/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 22-2-2019 */

`ifdef MULTICORE2PLUS
    `define MC2_PINS
`endif

`ifdef MULTICORE2
    `define MC2_PINS
`endif

module neptuno_top(
    input           CLK50,
    output  [5:0]   VGA_R,
    output  [5:0]   VGA_G,
    output  [5:0]   VGA_B,
    output          VGA_HS,
    output          VGA_VS,
    // SDRAM interface
    inout  [15:0]   SDRAM_DQ,       // SDRAM Data bus 16 Bits
    output [12:0]   SDRAM_A,        // SDRAM Address bus 13 Bits
    output          SDRAM_DQML,     // SDRAM Low-byte Data Mask
    output          SDRAM_DQMH,     // SDRAM High-byte Data Mask
    output          SDRAM_nWE,      // SDRAM Write Enable
    output          SDRAM_nCAS,     // SDRAM Column Address Strobe
    output          SDRAM_nRAS,     // SDRAM Row Address Strobe
    output          SDRAM_nCS,      // SDRAM Chip Select
    output [1:0]    SDRAM_BA,       // SDRAM Bank Address
    inout           SDRAM_CLK,      // SDRAM Clock
    output          SDRAM_CKE,      // SDRAM Clock Enable
   // SPI interface to arm io controller
    inout           SPI_DO,
    input           SPI_DI,
    input           SPI_SCK,
    input           SPI_SS2,
    // sound
    output          AUDIO_L,
    output          AUDIO_R,
    // user LED
    output          LED,

    // NeptUNO exclusive pins
    // PS2
    input           PS2_CLK,
    input           PS2_DATA,
    inout           PS2_MOUSE_CLK,
    inout           PS2_MOUSE_DATA
    
    // Joystick
`ifndef MULTICORE2
    // joy pins for neputo and Multicore 2 plus
    ,output         JOY_CLK,
    output          JOY_LOAD,
    input           JOY_DATA
`else
    //joy pins for Multicore 2
   ,input [5:0]     JOY1,
    input [5:0]     JOY2
`endif

    ,output          JOY_SELECT

`ifdef MC2_PINS
    // only MC2 and MC2+ pins
    ,input [3:0]     BUTTON_n,
    
    // SD Card
    output wire SD_CS,
    output wire SD_SCLK,
    output wire SD_MOSI,
    input wire  SD_MISO,   
    
    // SRAM
    output wire [20:0]SRAM_ADDR,
    inout wire  [7:0]SRAM_DATA,
    output wire SRAM_WE,
    output wire SRAM_OE 
`endif

    //STM32
    ,output wire  STM_RESET,
    output wire   SPI_nWAIT
        
`ifdef MULTICORE2PLUS
    //Multicore 2 plus exclusive pins
    ,inout [31:0] GPIO 
`endif   

`ifdef SIMULATION
    ,output         sim_pxl_cen,
    output          sim_pxl_clk,
    output          sim_vb,
    output          sim_hb
`endif
);

//---------------------------------------------------------
//-- Multicores defaults
//---------------------------------------------------------
`ifdef MC2_PINS    
    //no SRAM for this core
    assign SRAM_WE  = 1'b1;
    assign SRAM_OE  = 1'b1;

    //all the SD reading goes thru the microcontroller for this core
    assign SD_CS   = 1'bZ;
    assign SD_SCLK = 1'bZ;
    assign SD_MOSI = 1'bZ;
    
    assign STM_RESET = 1'bZ;
`endif  

`ifdef MULTICORE2PLUS    
   //disable external interfaces for this core
    assign GPIO = 32'Hzzzz; 
`endif  

`ifdef JTFRAME_SDRAM_LARGE
    localparam SDRAMW=23; // 64 MB
`else
    localparam SDRAMW=22; // 32 MB
`endif

wire          rst, rst_n, clk_sys, clk_rom, clk6, clk24, clk48, clk96;
wire [63:0]   status;
wire [31:0]   joystick1, joystick2;
wire [24:0]   ioctl_addr;
wire [ 7:0]   ioctl_data;
wire [ 7:0]   ioctl_data2sd;
wire          ioctl_wr;
wire          ioctl_ram;

wire [15:0]   joystick_analog_0, joystick_analog_1;

wire rst_req   = status[0];

// ROM download
wire          downloading, dwnld_busy;

wire [SDRAMW-1:0] prog_addr;
wire [15:0]   prog_data;
`ifndef JTFRAME_SDRAM_BANKS
wire [ 7:0]   prog_data8;
`endif
wire [ 1:0]   prog_mask, prog_ba;
wire          prog_we, prog_rd, prog_rdy, prog_ack, prog_dst, prog_dok;

// ROM access from game
wire [SDRAMW-1:0] ba0_addr, ba1_addr, ba2_addr, ba3_addr;
wire [ 3:0] ba_rd, ba_rdy, ba_ack, ba_dst, ba_dok;
wire        ba_wr;
wire [15:0] ba0_din;
wire [ 1:0] ba0_din_m;
wire [15:0] sdram_dout;

`ifndef COLORW
`define COLORW 4
`endif

`ifndef MC2_PINS
    wire [3:0] BUTTON_n = 4'hf;
`endif

localparam COLORW=`COLORW;

wire [COLORW-1:0] red;
wire [COLORW-1:0] green;
wire [COLORW-1:0] blue;

wire LHBL, LVBL, hs, vs;
wire [15:0] snd_left, snd_right;

wire [9:0] game_joy1, game_joy2, game_joy3, game_joy4;
wire [3:0] game_coin, game_start;
wire       game_rst, game_service;
wire [3:0] gfx_en;
// SDRAM
wire data_rdy, sdram_ack;

// PLL's
wire pll_locked, clk_pico;

`ifndef STEREO_GAME
assign snd_right = snd_left;
`endif

//joysticks
wire [5:0] joy1_s;
wire [5:0] joy2_s;

`ifndef MULTICORE2
    joystick_serial u_serial(
        .clk_i           ( clk_sys    ),
        .joy_data_i      ( JOY_DATA   ),
        .joy_clk_o       ( JOY_CLK    ),
        .joy_load_o      ( JOY_LOAD   ),

        .joy1_up_o       ( joy1_s[3] ),
        .joy1_down_o     ( joy1_s[2] ),
        .joy1_left_o     ( joy1_s[1] ),
        .joy1_right_o    ( joy1_s[0] ),
        .joy1_fire1_o    ( joy1_s[4] ),
        .joy1_fire2_o    ( joy1_s[5] ),

        .joy2_up_o       ( joy2_s[3] ),
        .joy2_down_o     ( joy2_s[2] ),
        .joy2_left_o     ( joy2_s[1] ),
        .joy2_right_o    ( joy2_s[0] ),
        .joy2_fire1_o    ( joy2_s[4] ),
        .joy2_fire2_o    ( joy2_s[5] )
    );
`else
    assign joy1_s = JOY1;
    assign joy2_s = JOY2;
`endif


jtframe_mist_clocks u_clocks(
    .clk_ext    ( CLK50          ),    // 27MHz for MiST, 50MHz for Neptuno

    // PLL outputs
    .clk96      ( clk96          ),
    .clk48      ( clk48          ),
    .clk24      ( clk24          ),
    .clk6       ( clk6           ),
    .pll_locked ( pll_locked     ),

    // System clocks
    .clk_sys    ( clk_sys        ),
    .clk_rom    ( clk_rom        ),
    .SDRAM_CLK  ( SDRAM_CLK      )
);

assign clk_pico = clk48;


wire [7:0] dipsw_a, dipsw_b;
wire [7:0] debug_bus;
wire [1:0] dip_fxlevel, game_led;
wire       enable_fm, enable_psg;
wire       dip_pause, dip_flip, dip_test;
wire       pxl_cen, pxl2_cen;

`ifdef SIMULATION
assign sim_pxl_clk = clk_sys;
assign sim_pxl_cen = pxl_cen;
assign sim_vb = ~LVBL;
assign sim_hb = ~LHBL;
`endif

`ifndef SIGNED_SND
`define SIGNED_SND 1'b1
`endif

`ifndef BUTTONS
`define BUTTONS 2
`endif

`ifdef JTFRAME_MIST_DIPBASE
localparam DIPBASE=`JTFRAME_MIST_DIPBASE;
`else
localparam DIPBASE=16;
`endif

assign game_led[1] = 1'b0; // Let system LED info go through too

localparam BUTTONS=`BUTTONS;

jtframe_mist #(
    .SDRAMW       ( SDRAMW         ),
    .SIGNED_SND   ( `SIGNED_SND    ),
    .BUTTONS      ( BUTTONS        ),
    .DIPBASE      ( DIPBASE        ),
    .COLORW       ( COLORW         )
    `ifdef VIDEO_WIDTH
    ,.VIDEO_WIDTH   ( `VIDEO_WIDTH   )
    `endif
    `ifdef VIDEO_HEIGHT
    ,.VIDEO_HEIGHT  ( `VIDEO_HEIGHT  )
    `endif
)
u_frame(
    .clk_sys        ( clk_sys        ),
    .clk_rom        ( clk_rom        ),
    .clk_pico       ( clk_pico       ),
    .pll_locked     ( pll_locked     ),
    .status         ( status         ),
    // Base video
    .game_r         ( red            ),
    .game_g         ( green          ),
    .game_b         ( blue           ),
    .LHBL           ( LHBL           ),
    .LVBL           ( LVBL           ),
    .hs             ( hs             ),
    .vs             ( vs             ),
    .pxl_cen        ( pxl_cen        ),
    .pxl2_cen       ( pxl2_cen       ),
    // MiST VGA pins
    .VGA_R          ( VGA_R          ),
    .VGA_G          ( VGA_G          ),
    .VGA_B          ( VGA_B          ),
    .VGA_HS         ( VGA_HS         ),
    .VGA_VS         ( VGA_VS         ),
    // LED
    .game_led       ( game_led       ),
    // SDRAM interface
    .SDRAM_DQ       ( SDRAM_DQ       ),
    .SDRAM_A        ( SDRAM_A        ),
    .SDRAM_DQML     ( SDRAM_DQML     ),
    .SDRAM_DQMH     ( SDRAM_DQMH     ),
    .SDRAM_nWE      ( SDRAM_nWE      ),
    .SDRAM_nCAS     ( SDRAM_nCAS     ),
    .SDRAM_nRAS     ( SDRAM_nRAS     ),
    .SDRAM_nCS      ( SDRAM_nCS      ),
    .SDRAM_BA       ( SDRAM_BA       ),
    .SDRAM_CKE      ( SDRAM_CKE      ),
    // SPI interface to arm io controller
    .SPI_DO         ( SPI_DO         ),
    .SPI_DI         ( SPI_DI         ),
    .SPI_SCK        ( SPI_SCK        ),
    .SPI_SS2        ( SPI_SS2        ),

    .joy1_bus       ( joy1_s         ),
    .joy2_bus       ( joy2_s         ),

    .JOY_SELECT     ( JOY_SELECT     ),

    .ps2_clk        ( PS2_CLK        ),
    .ps2_dout       ( PS2_DATA       ),
    
    .BUTTON_n       ( BUTTON_n       ),

    // ROM access from game
    // Bank 0: allows R/W
    .ba0_addr   ( ba0_addr      ),
    .ba1_addr   ( ba1_addr      ),
    .ba2_addr   ( ba2_addr      ),
    .ba3_addr   ( ba3_addr      ),
    .ba_rd      ( ba_rd         ),
    .ba_wr      ({ 3'd0, ba_wr }),
    .ba_dst     ( ba_dst        ),
    .ba_dok     ( ba_dok        ),
    .ba_rdy     ( ba_rdy        ),
    .ba_ack     ( ba_ack        ),
    .ba0_din    ( ba0_din       ),
    .ba0_din_m  ( ba0_din_m     ),  // write mask

    // ROM-load interface
    .prog_addr  ( prog_addr     ),
    .prog_ba    ( prog_ba       ),
    .prog_rd    ( prog_rd       ),
    .prog_we    ( prog_we       ),
    .prog_data  ( prog_data     ),
    .prog_mask  ( prog_mask     ),
    .prog_ack   ( prog_ack      ),
    .prog_dst   ( prog_dst      ),
    .prog_dok   ( prog_dok      ),
    .prog_rdy   ( prog_rdy      ),

    // ROM load
    .ioctl_addr     ( ioctl_addr     ),
    .ioctl_data     ( ioctl_data     ),
    .ioctl_data2sd  ( ioctl_data2sd  ),
    .ioctl_wr       ( ioctl_wr       ),
    .ioctl_ram      ( ioctl_ram      ),

    .downloading    ( downloading    ),
    .dwnld_busy     ( dwnld_busy     ),

    .sdram_dout     ( sdram_dout     ),
//////////// board
    .rst            ( rst            ),
    .rst_n          ( rst_n          ), // unused
    .game_rst       ( game_rst       ),
    .game_rst_n     (                ),
    // reset forcing signals:
    .rst_req        ( rst_req        ),
    // Sound
    .snd_left       ( snd_left       ),
    .snd_right      ( snd_right      ),
    .AUDIO_L        ( AUDIO_L        ),
    .AUDIO_R        ( AUDIO_R        ),
    // joystick
    .game_joystick1 ( game_joy1      ),
    .game_joystick2 ( game_joy2      ),
    .game_joystick3 ( game_joy3      ),
    .game_joystick4 ( game_joy4      ),
    .game_coin      ( game_coin      ),
    .game_start     ( game_start     ),
    .game_service   ( game_service   ),
    .joystick_analog_0( joystick_analog_0 ),
    .joystick_analog_1( joystick_analog_1 ),
    .LED            ( LED            ),
    // DIP and OSD settings
    .enable_fm      ( enable_fm      ),
    .enable_psg     ( enable_psg     ),
    .dip_test       ( dip_test       ),
    .dip_pause      ( dip_pause      ),
    .dip_flip       ( dip_flip       ),
    .dip_fxlevel    ( dip_fxlevel    ),
    // Debug
    .gfx_en         ( gfx_en         ),
    .debug_bus      ( debug_bus      )
);

`ifdef SIMULATION
`ifdef TESTINPUTS
    test_inputs u_test_inputs(
        .loop_rst       ( downloading    ),
        .LVBL           ( LVBL           ),
        .game_joystick1 ( game_joy1[6:0] ),
        .button_1p      ( game_start[0]  ),
        .coin_left      ( game_coin[0]   )
    );
    assign game_start[1] = 1'b1;
    assign game_coin[1]  = 1'b1;
    assign game_joystick2 = ~10'd0;
    assign game_joystick3 = ~10'd0;
    assign game_joystick4 = ~10'd0;
    assign game_joystick1[9:7] = 3'b111;
    assign sim_vb = vs;
    assign sim_hb = hs;
`endif
`endif

wire sample;

`ifdef JTFRAME_4PLAYERS
localparam STARTW=4;
`else
localparam STARTW=2;
`endif

// For simulation, either ~32'd0 or `JTFRAME_SIM_DIPS will be used for DIPs
`ifdef SIMULATION
`ifndef JTFRAME_SIM_DIPS
    `define JTFRAME_SIM_DIPS ~32'd0
`endif
`endif

`ifdef JTFRAME_SIM_DIPS
    wire [31:0] dipsw = `JTFRAME_SIM_DIPS;
`else
    wire [31:0] dipsw = status[31+DIPBASE:DIPBASE];
`endif

`GAMETOP
u_game(
    .rst         ( game_rst       ),
    // The main clock is always the same one as the SDRAM
    .clk         ( clk_rom        ),
    `ifdef JTFRAME_CLK96
    .clk96       ( clk96          ),
    `endif
    `ifdef JTFRAME_CLK48
    .clk48       ( clk48          ),
    `endif
    `ifdef JTFRAME_CLK24
    .clk24       ( clk24          ),
    `endif
    `ifdef JTFRAME_CLK6
    .clk6        ( clk6           ),
    `endif
    // Video
    .pxl2_cen    ( pxl2_cen       ),
    .pxl_cen     ( pxl_cen        ),
    .red         ( red            ),
    .green       ( green          ),
    .blue        ( blue           ),
    .LHBL_dly    ( LHBL           ),
    .LVBL_dly    ( LVBL           ),
    .HS          ( hs             ),
    .VS          ( vs             ),
    // LED
    .game_led    ( game_led[0]    ),

    .start_button( game_start[STARTW-1:0]      ),
    .coin_input  ( game_coin[STARTW-1:0]       ),
    .joystick1   ( game_joy1[BUTTONS+3:0]      ),
    .joystick2   ( game_joy2[BUTTONS+3:0]      ),
    `ifdef JTFRAME_4PLAYERS
    .joystick3   ( game_joy3[BUTTONS+3:0]      ),
    .joystick4   ( game_joy4[BUTTONS+3:0]      ),
    `endif
    `ifdef JTFRAME_ANALOG
    .joyana1     ( joystick_analog_0   ),
    .joyana2     ( joystick_analog_1   ),
    `endif

    // Sound control
    .enable_fm   ( enable_fm      ),
    .enable_psg  ( enable_psg     ),
    // PROM programming
    .ioctl_addr  ( ioctl_addr     ),
    .ioctl_data  ( ioctl_data     ),
    .ioctl_wr    ( ioctl_wr       ),
`ifdef CORE_NVRAM_SIZE
    .ioctl_ram   ( ioctl_ram      ),
    .ioctl_data2sd(ioctl_data2sd  ),
`endif
    // ROM load
    .downloading ( downloading    ),
    .dwnld_busy  ( dwnld_busy     ),
    .data_read   ( sdram_dout     ),

`ifdef JTFRAME_SDRAM_BANKS
    // Bank 0: allows R/W
    .ba0_addr   ( ba0_addr      ),
    .ba1_addr   ( ba1_addr      ),
    .ba2_addr   ( ba2_addr      ),
    .ba3_addr   ( ba3_addr      ),
    .ba_rd      ( ba_rd         ),
    .ba_wr      ( ba_wr         ),
    .ba_dst     ( ba_dst        ),
    .ba_dok     ( ba_dok        ),
    .ba_rdy     ( ba_rdy        ),
    .ba_ack     ( ba_ack        ),
    .ba0_din    ( ba0_din       ),
    .ba0_din_m  ( ba0_din_m     ),  // write mask

    .prog_ba    ( prog_ba       ),
    .prog_rdy   ( prog_rdy      ),
    .prog_ack   ( prog_ack      ),
    .prog_dok   ( prog_dok      ),
    .prog_dst   ( prog_dst      ),
    .prog_data  ( prog_data     ),
`else
    .sdram_req  ( ba_rd[0]      ),
    .sdram_addr ( ba0_addr      ),
    .data_dst   ( ba_dst[0] | prog_dst ),
    .data_rdy   ( ba_rdy[0] | prog_rdy ),
    .sdram_ack  ( ba_ack[0] | prog_ack ),

    .prog_data  ( prog_data8    ),
`endif

    // common ROM-load interface
    .prog_addr  ( prog_addr     ),
    .prog_rd    ( prog_rd       ),
    .prog_we    ( prog_we       ),
    .prog_mask  ( prog_mask     ),

    // DIP switches
    .status      ( status[31:0]   ),
    .dip_pause   ( dip_pause      ),
    .dip_flip    ( dip_flip       ),
    .dip_test    ( dip_test       ),
    .dip_fxlevel ( dip_fxlevel    ),
    .service     ( game_service   ),
    `ifdef JTFRAME_MRA_DIP
    .dipsw       ( dipsw          ),
    `endif

    // sound
    `ifndef STEREO_GAME
    .snd         ( snd_left       ),
    `else
    .snd_left    ( snd_left       ),
    .snd_right   ( snd_right      ),
    `endif
    .sample      ( sample         ),
    // Debug
    .gfx_en      ( gfx_en         )
    `ifdef JTFRAME_DEBUG
    ,.debug_bus   ( debug_bus      )
    `endif
);

`ifndef JTFRAME_SDRAM_BANKS
    assign prog_ba   = 2'd0;
    // tie down unused bank signals
    assign ba1_addr = 22'd0;
    assign ba2_addr = 22'd0;
    assign ba2_ack  = 0;
    assign ba3_addr = 22'd0;
    assign prog_data = {2{prog_data8}};
    assign ba_rd[3:1] = 0;
    assign ba_wr      = 0;
`endif

`ifdef SIMULATION
integer fsnd;
initial begin
    fsnd=$fopen("sound.raw","wb");
end
always @(posedge sample) begin
    $fwrite(fsnd,"%u", {snd_left, snd_right});
end
`endif

endmodule
