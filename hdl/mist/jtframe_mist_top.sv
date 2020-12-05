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

// This is the MiST top level

module mist_top(
    input   [1:0]   CLOCK_27,
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
    output          SDRAM_CLK,      // SDRAM Clock
    output          SDRAM_CKE,      // SDRAM Clock Enable
   // SPI interface to arm io controller
    inout           SPI_DO,
    input           SPI_DI,
    input           SPI_SCK,
    input           SPI_SS2,
    input           SPI_SS3,
    input           SPI_SS4,
    input           CONF_DATA0,
    // sound
    output          AUDIO_L,
    output          AUDIO_R,
    // user LED
    output          LED
    `ifdef SIMULATION
    ,output         sim_pxl_cen,
    output          sim_pxl_clk,
    output          sim_vb,
    output          sim_hb
    `endif
);

`ifdef SIMULATION
localparam CONF_STR="JTGNG;;";
`else
// Config string
`define SEPARATOR "",

localparam CONF_STR = {
    `CORENAME,";;",
    // Common MiSTer options
    `ifndef JTFRAME_OSD_NOLOAD
    "F,rom;",
    `endif
    `ifdef VERTICAL_SCREEN
    `ifdef JTFRAME_OSD_FLIP
    "O1,Flip screen,Off,On;",
    `endif
    "O2,Rotate controls,No,Yes;",
    `endif
    // `ifdef JOIN_JOYSTICKS
    // "OE,Separate Joysticks,Yes,No;",    // If no, then player 2 joystick
    //     // is assimilated to player 1 joystick
    // `endif
    "O34,Video Mode, pass thru, linear, analogue, dark;",
    `ifndef JTFRAME_OSD_NOSND
        `ifdef JT12
        "O67,FX volume, high, very high, very low, low;",
        "O8,PSG,On,Off;",
        "O9,FM ,On,Off;",
        `else
            `ifdef JTFRAME_ADPCM
            "O8,ADPCM,On,Off;",
            `endif
            `ifdef JT51
            "O9,FM ,On,Off;",
            `endif
        `endif
    `endif
    `ifdef JTFRAME_OSD_TEST
    "OA,Test mode,Off,On;",
    `endif
    `ifndef JTFRAME_OSD_NOCREDITS
    "OC,Credits,Off,On;",
    `endif
    `SEPARATOR
    `ifdef JTFRAME_MRA_DIP
        "DIP;",
    `endif
    `ifdef CORE_OSD
        `CORE_OSD
    `endif
    "T0,RST;",
    "V,patreon.com/topapate;"
};

`undef SEPARATOR`endif

wire          rst, rst_n, clk_sys, clk_rom, clk6, clk24;
wire [63:0]   status;
wire [31:0]   joystick1, joystick2;
wire [21:0]   sdram_addr;
wire [31:0]   data_read;
wire          loop_rst;
wire          downloading, dwnld_busy;
wire [24:0]   ioctl_addr;
wire [ 7:0]   ioctl_data;
wire          ioctl_wr;

wire [ 1:0]   sdram_wrmask, sdram_bank;
wire          sdram_rnw;
wire [15:0]   data_write;
wire [15:0]   joystick_analog_0, joystick_analog_1;

`ifndef JTFRAME_WRITEBACK
assign sdram_wrmask = 2'b11;
assign sdram_rnw    = 1'b1;
assign data_write   = 16'h00;
`endif

wire rst_req   = status[0];

wire sdram_req;

wire [21:0]   prog_addr;
wire [ 7:0]   prog_data;
wire [ 1:0]   prog_mask, prog_bank;
wire          prog_we, prog_rd;

`ifndef COLORW
`define COLORW 4
`endif

localparam COLORW=`COLORW;

wire [COLORW-1:0] red;
wire [COLORW-1:0] green;
wire [COLORW-1:0] blue;

wire LHBL, LVBL, hs, vs;
wire [15:0] snd_left, snd_right;

`ifndef STEREO_GAME
assign snd_right = snd_left;
`endif

wire [9:0] game_joy1, game_joy2, game_joy3, game_joy4;
wire [3:0] game_coin, game_start;
wire game_rst;
wire [3:0] gfx_en;
// SDRAM
wire data_rdy, sdram_ack;
wire refresh_en;


// PLL's
wire clk_vga_in, clk_vga, pll_locked;

`ifdef JTFRAME_CLK96
wire clk48;

jtframe_pll96 u_pll_game (
    .inclk0 ( CLOCK_27[0] ),
    .c0     ( clk48       ), // 48 MHz
    .c1     ( clk_rom     ), // 96 MHz
    .c2     ( SDRAM_CLK   ), // 96 MHz shifted
    .c3     ( clk24       ),
    .c4     ( clk6        ),
    .locked ( pll_locked  )
);
assign clk_sys   = clk_rom; // it is possible to use clk48 instead but
    // video mixer doesn't work well in HQ mode
`else
jtframe_pll0 u_pll_game (
    .inclk0 ( CLOCK_27[0] ),
    .c1     ( clk_rom     ), // 48 MHz
    .c2     ( SDRAM_CLK   ),
    .c3     ( clk24       ),
    .c4     ( clk6        ),
    .locked ( pll_locked  )
);
assign clk_sys   = clk_rom;
`endif

jtframe_pll1 u_pll_vga (
    .inclk0 ( clk_sys    ),
    .c0     ( clk_vga    ) // 25
);

wire [7:0] dipsw_a, dipsw_b;
wire [1:0] dip_fxlevel;
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

localparam BUTTONS=`BUTTONS;

jtframe_mist #(
    .CONF_STR     ( CONF_STR       ),
    .SIGNED_SND   ( `SIGNED_SND    ),
    .BUTTONS      ( BUTTONS        ),
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
    .clk_vga        ( clk_vga        ),
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
    // SDRAM interface
    .SDRAM_CLK      ( SDRAM_CLK      ),
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
    .SPI_SS3        ( SPI_SS3        ),
    .SPI_SS4        ( SPI_SS4        ),
    .CONF_DATA0     ( CONF_DATA0     ),
    // ROM
    .ioctl_addr     ( ioctl_addr     ),
    .ioctl_data     ( ioctl_data     ),
    .ioctl_wr       ( ioctl_wr       ),
    .prog_addr      ( prog_addr      ),
    .prog_data      ( prog_data      ),
    .prog_mask      ( prog_mask      ),
    .prog_we        ( prog_we        ),
    .prog_rd        ( prog_rd        ),
    .prog_bank      ( prog_bank      ),
    .downloading    ( downloading    ),
    .dwnld_busy     ( dwnld_busy     ),
    // ROM access from game
    .loop_rst       ( loop_rst       ),
    .sdram_addr     ( sdram_addr     ),
    .sdram_req      ( sdram_req      ),
    .sdram_ack      ( sdram_ack      ),
    .sdram_bank     ( sdram_bank     ),
    .data_read      ( data_read      ),
    .data_rdy       ( data_rdy       ),
    .refresh_en     ( refresh_en     ),
    // write support
    .sdram_wrmask   ( sdram_wrmask   ),
    .sdram_rnw      ( sdram_rnw      ),
    .data_write     ( data_write     ),
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
    .game_service   (                ), // unused
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
    .gfx_en         ( gfx_en         )
);

`ifdef SIMULATION
`ifdef TESTINPUTS
    test_inputs u_test_inputs(
        .loop_rst       ( loop_rst       ),
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

`ifdef JTFRAME_MIST_DIPBASE
localparam DIPBASE=`JTFRAME_MIST_DIPBASE;
`else
localparam DIPBASE=16;
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
    .clk         ( clk_rom        ),
    `ifdef JTFRAME_CLK96
    .clk48       ( clk48          ),
    `endif
    `ifdef JTFRAME_CLK24
    .clk24       ( clk24          ),
    `endif
    `ifdef JTFRAME_CLK6
    .clk6        ( clk6           ),
    `endif
    .pxl2_cen    ( pxl2_cen       ),
    .pxl_cen     ( pxl_cen        ),
    .red         ( red            ),
    .green       ( green          ),
    .blue        ( blue           ),
    .LHBL_dly    ( LHBL           ),
    .LVBL_dly    ( LVBL           ),
    .HS          ( hs             ),
    .VS          ( vs             ),

    .start_button( game_start[STARTW-1:0]      ),
    .coin_input  ( game_coin[STARTW-1:0]       ),
    .joystick1   ( game_joy1[BUTTONS+3:0]      ),
    .joystick2   ( game_joy2[BUTTONS+3:0]      ),
    `ifdef JTFRAME_4PLAYERS
    .joystick3   ( game_joy3[BUTTONS+3:0]      ),
    .joystick4   ( game_joy4[BUTTONS+3:0]      ),
    `endif
    `ifdef JTFRAME_ANALOG
    .joystick_analog_0( joystick_analog_0   ),
    .joystick_analog_1( joystick_analog_1   ),
    `endif

    // Sound control
    .enable_fm   ( enable_fm      ),
    .enable_psg  ( enable_psg     ),
    // PROM programming
    .ioctl_addr  ( ioctl_addr     ),
    .ioctl_data  ( ioctl_data     ),
    .ioctl_wr    ( ioctl_wr       ),
    .prog_addr   ( prog_addr      ),
    .prog_data   ( prog_data      ),
    .prog_mask   ( prog_mask      ),
    .prog_we     ( prog_we        ),
    .prog_rd     ( prog_rd        ),
    `ifdef JTFRAME_SDRAM_BANKS
    .prog_bank   ( prog_bank      ),
    .sdram_bank  ( sdram_bank     ),
    `endif
    // ROM load
    .downloading ( downloading    ),
    .dwnld_busy  ( dwnld_busy     ),
    .loop_rst    ( loop_rst       ),
    .sdram_req   ( sdram_req      ),
    .sdram_addr  ( sdram_addr     ),
    .data_read   ( data_read      ),
    .sdram_ack   ( sdram_ack      ),
    .data_rdy    ( data_rdy       ),
    .refresh_en  ( refresh_en     ),
    `ifdef JTFRAME_WRITEBACK
    .sdram_wrmask( sdram_wrmask   ),
    .sdram_rnw   ( sdram_rnw      ),
    .data_write  ( data_write     ),
    `endif

    // DIP switches
    .status      ( status         ),
    .dip_pause   ( dip_pause      ),
    .dip_flip    ( dip_flip       ),
    .dip_test    ( dip_test       ),
    .dip_fxlevel ( dip_fxlevel    ),
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
);

`ifndef JTFRAME_SDRAM_BANKS
assign sdram_bank = 2'b0;
assign prog_bank  = 2'b0;
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