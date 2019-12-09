library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

library work;
use work.zpupkg.ALL;

entity data_io is
	port (
		clk 			: in std_logic;
		reset_n 	: in std_logic;
		-- Sram
		sram_addr_w : buffer   std_logic_vector(21 downto 0);
		sram_data_w : out   std_logic_vector(7  downto 0);  
		sram_we     : buffer std_logic;
		-- SD card interface
		spi_miso		: in std_logic := '1';
		spi_mosi		: out std_logic;
		spi_clk		: out std_logic;
		spi_cs 		: out std_logic;
		-- Rom loading Signal
		rom_loading: out std_logic	
	);
end entity;

architecture rtl of data_io is

-- ZPU signals
constant maxAddrBit : integer := 20; -- Optional - defaults to 32 - but helps keep the logic element count down.
signal mem_busy           : std_logic;
signal mem_read             : std_logic_vector(wordSize-1 downto 0);
signal mem_write            : std_logic_vector(wordSize-1 downto 0);
signal mem_addr             : std_logic_vector(maxAddrBit downto 0);
signal mem_writeEnable      : std_logic; 
signal mem_readEnable       : std_logic;
signal mem_hEnable      : std_logic; 
signal mem_bEnable      : std_logic; 

signal zpu_to_rom : ZPU_ToROM;
signal zpu_from_rom : ZPU_FromROM;

-- Interrupt signals
constant int_max : integer := 1;
signal int_triggers : std_logic_vector(int_max downto 0);
signal int_status : std_logic_vector(int_max downto 0);
signal int_ack : std_logic;
signal int_req : std_logic;
signal int_enabled : std_logic :='0'; -- Disabled by default


-- SPI Clock counter
signal spi_tick : unsigned(8 downto 0);
signal spiclk_in : std_logic;
signal spi_fast : std_logic;

-- SPI signals
signal host_to_spi : std_logic_vector(7 downto 0);
signal spi_to_host : std_logic_vector(7 downto 0);
signal spi_trigger : std_logic;
signal spi_busy : std_logic;
signal spi_active : std_logic;

		-- Boot upload signals
signal host_bootdata     : std_logic_vector(31 downto 0);
signal host_bootdata_req : std_logic;
signal host_bootdata_ack : std_logic :='0';
signal host_reset_n      : std_logic;
signal size              : std_logic_vector(31 downto 0);
signal rom_load          : std_logic := '0';
signal rom_loaded        : std_logic := '0';
signal rom_load_start    : std_logic := '0';
signal rom_load_end      : std_logic := '0';

    type boot_states is (idle, ramwait);
    signal boot_state : boot_states := idle;
	 signal ram_step : integer := 0;
	 signal rclkD  : std_logic := '0';
	 signal rclkD2 : std_logic := '0';

begin

-- ROM

	myrom : entity work.CtrlROM_ROM
	generic map
	(
		maxAddrBitBRAM => 11 --11 Bits 4095 Bytes (4Ks)
	)
	port map (
		clk => clk,
		from_zpu => zpu_to_rom,
		to_zpu => zpu_from_rom
	);

	
-- Main CPU
-- We instantiate the CPU with the optional instructions enabled, which allows us to reduce
-- the size of the ROM by leaving out emulation code.
	zpu: zpu_core_flex
	generic map (
		IMPL_MULTIPLY => true,
		IMPL_COMPARISON_SUB => true,
		IMPL_EQBRANCH => true,
		IMPL_STOREBH => true,
		IMPL_LOADBH => true,
		IMPL_CALL => true,
		IMPL_SHIFT => true,
		IMPL_XOR => true,
		CACHE => true,	-- Modest speed-up when running from ROM
--		IMPL_EMULATION => minimal, -- Emulate only byte/halfword accesses, with alternateive emulation table
		REMAP_STACK => false, -- We're not using SDRAM so no need to remap the Boot ROM / Stack RAM
		EXECUTE_RAM => false, -- We don't need to execute code from external RAM.
		maxAddrBit => maxAddrBit,
		maxAddrBitBRAM => 11
	)
	port map (
		clk                 => clk,
		reset               => not reset_n,
		in_mem_busy         => mem_busy,
		mem_read            => mem_read,
		mem_write           => mem_write,
		out_mem_addr        => mem_addr,
		out_mem_writeEnable => mem_writeEnable,
		out_mem_hEnable     => mem_hEnable,
		out_mem_bEnable     => mem_bEnable,
		out_mem_readEnable  => mem_readEnable,
		from_rom => zpu_from_rom,
		to_rom => zpu_to_rom,
		interrupt => int_req
	);

-- SPI Timer
process(clk)
begin
	if rising_edge(clk) then
		spiclk_in<='0';
		spi_tick<=spi_tick+1;
		if (spi_fast='1' and spi_tick(5)='1') or spi_tick(8)='1' then
			spiclk_in<='1'; -- Momentary pulse for SPI host.
			spi_tick<='0'&X"00";
		end if;
	end if;
end process;


-- SD Card host

spi : entity work.spi_interface
	port map(
		sysclk => clk,
		reset => reset_n,

		-- Host interface
		spiclk_in => spiclk_in,
		host_to_spi => host_to_spi,
		spi_to_host => spi_to_host,
		trigger => spi_trigger,
		busy => spi_busy,

		-- Hardware interface
		miso => spi_miso,
		mosi => spi_mosi,
		spiclk_out => spi_clk
	);

		
-- Interrupt controller

intcontroller: entity work.interrupt_controller
generic map (
	max_int => int_max
)
port map (
	clk => clk,
	reset_n => reset_n,
	enable => int_enabled,
	trigger => int_triggers,
	ack => int_ack,
	int => int_req,
	status => int_status
);

int_triggers<=(0=>'1',
					others => '0');

process(clk,reset_n)
begin
	if reset_n='0' then
		int_enabled<='0';
		host_reset_n <='0';
		host_bootdata_req<='0';
		spi_active<='0';
		spi_cs<='1';
	elsif rising_edge(clk) then
		mem_busy<='1';
		int_ack<='0';
		spi_trigger<='0';

		-- Write from CPU?
		if mem_writeEnable='1' then
			case mem_addr(maxAddrBit)&mem_addr(10 downto 8) is
				when X"F" =>	-- Peripherals at 0xFFFFFF00
					case mem_addr(7 downto 0) is

						when X"B0" => -- Interrupts
							int_enabled<=mem_write(0);
							mem_busy<='0';

						when X"D0" => -- SPI CS
							spi_cs<=not mem_write(0);
							spi_fast<=mem_write(8);
							mem_busy<='0';

						when X"D4" => -- SPI Data (blocking)
							spi_trigger<='1';
							host_to_spi<=mem_write(7 downto 0);
							spi_active<='1';

						when X"E8" => -- Host boot data
							-- Note that we don't clear mem_busy here; it's set instead when the ack signal comes in.
							host_bootdata<=mem_write;
							host_bootdata_req<='1';

						when X"EC" => -- Host control
							mem_busy<='0';
							host_reset_n<=not mem_write(0);
							
						when X"F8" => -- ROM Size
							mem_busy<='0';
							size<=mem_write(31 downto 0);
							
						when others =>
							mem_busy<='0';
							null;
					end case;
				when others =>
					mem_busy<='0';
			end case;

		-- Read from CPU?
		elsif mem_readEnable='1' then
			case mem_addr(maxAddrBit)&mem_addr(10 downto 8) is
				when X"F" =>	-- Peripherals
					case mem_addr(7 downto 0) is
					
						when X"B0" => -- Read from Interrupt status register
							mem_read<=(others=>'X');
							mem_read(int_max downto 0)<=int_status;
							int_ack<='1';
							mem_busy<='0';

						when X"D0" => -- SPI Status
							mem_read<=(others=>'X');
							mem_read(15)<=spi_busy;
							mem_busy<='0';

						when X"D4" => -- SPI read (blocking)
							spi_active<='1';
						when others =>
							mem_busy<='0';
							null;
					end case;

				when others => -- SDRAM
					mem_busy<='0';
			end case;
		end if;

		-- Boot data termination - allow CPU to proceed once boot data is acknowleged:
		if host_bootdata_ack='1' then
			mem_busy<='0';
			host_bootdata_req<='0';
		end if;

		
		-- SPI cycle termination
		if spi_active='1' and spi_busy='0' then
			mem_read(7 downto 0)<=spi_to_host;
			mem_read(31 downto 8)<=(others => '0');
			spi_active<='0';
			mem_busy<='0';
		end if;
			
	end if; -- rising-edge(clk)

end process;

--rom_load  <= '0' when unsigned(size) = unsigned(sram_addr_w) else '1';
--rom_loaded <= rom_load;
--rom_loading <= sram_we or rom_loaded; --rom_load or rom_loaded or sram_we;
--rom_loading <= rom_load_start and not rom_load_end;

rom_loading <= not host_reset_n;

process(clk)
begin 
 if rising_edge(clk) and rclkD = '1' and rclkD2 ='0' then
  if unsigned(size)>0 and unsigned(size) = unsigned(sram_addr_w) then rom_load_end <= '1'; end if;
 end if;
end process;

-- State machine to receive and stash boot data in SRAM
process(clk)
begin 
 if rising_edge(clk) then
  rclkD <= spiclk_in;
  rclkD2 <= rclkD;
 end if;
end process;

process(clk, rclkD, rclkD2, host_bootdata_req)
begin
	if rising_edge(clk) then
		if reset_n='0' then
			sram_addr_w <= "0000000000000000000000";
			sram_we <= '0';
			host_bootdata_ack<='0';
			boot_state<=idle;
			ram_step <= 0;
		else
			host_bootdata_ack<='0';
			case boot_state is
				when idle =>
					if host_bootdata_req='1' and rclkD = '1' and rclkD2 ='0' then
						if    ram_step = 0 then sram_data_w<=host_bootdata(31 downto 24); ram_step <= ram_step + 1; 
						elsif ram_step = 1 then sram_data_w<=host_bootdata(23 downto 16); ram_step <= ram_step + 1; 
						elsif ram_step = 2 then sram_data_w<=host_bootdata(15 downto  8); ram_step <= ram_step + 1; 
						elsif ram_step = 3 then sram_data_w<=host_bootdata(7  downto  0); ram_step <= 0; host_bootdata_ack<='1'; end if;
						sram_we<='1';
					   rom_load_start <= '1';
						boot_state<=ramwait;
					end if;					
				when ramwait =>
						sram_addr_w<=std_logic_vector((unsigned(sram_addr_w)+1));
						sram_we<='0';						
						boot_state<=idle;
			end case;
		end if;
	end if;
end process;
	
end architecture;
