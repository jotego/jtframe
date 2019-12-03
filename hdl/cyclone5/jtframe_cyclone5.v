/*  This file is part of JT_GNG.
    JT_GNG program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT_GNG program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT_GNG.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 7-3-2019 */

`timescale 1ns/1ps

module jtframe_cyclone5(
    input wire          clk_sys,
    input wire          clk_rom,
    input wire          clk_vga,
    input wire          pll_locked,
    // interface with microcontroller
    output wire [31:0]  status,
    // Base video
    input wire  [3:0]   game_r,
    input wire  [3:0]   game_g,
    input wire  [3:0]   game_b,
    input wire          LHBL,
    input wire          LVBL,
    input wire          hs,
    input wire          vs,
    input wire          pxl_cen,
    input wire          pxl2_cen,
    // MiST VGA pins
    output wire [5:0]   VGA_R,
    output wire [5:0]   VGA_G,
    output wire [5:0]   VGA_B,
    output wire         VGA_HS,
    output wire         VGA_VS,
    // SDRAM interface
    inout  wire [15:0]   SDRAM_DQ,       // SDRAM Data bus 16 Bits
    output wire [12:0]   SDRAM_A,        // SDRAM Address bus 13 Bits
    output wire         SDRAM_DQML,     // SDRAM Low-byte Data Mask
    output wire         SDRAM_DQMH,     // SDRAM High-byte Data Mask
    output wire         SDRAM_nWE,      // SDRAM Write Enable
    output wire         SDRAM_nCAS,     // SDRAM Column Address Strobe
    output wire         SDRAM_nRAS,     // SDRAM Row Address Strobe
    output wire         SDRAM_nCS,      // SDRAM Chip Select
    output wire [1:0]    SDRAM_BA,       // SDRAM Bank Address
    output wire         SDRAM_CKE,      // SDRAM Clock Enable
    // SPI interface to arm io controller
    output wire         SD_CS_N,
	 output wire         SD_CLK,
	 output wire         SD_MOSI,
    input   wire        SD_MISO,
    // ROM load from SD
    output wire [21:0]   ioctl_addr,
    output wire [ 7:0]   ioctl_data,
    output wire         ioctl_wr,
    input wire [21:0]   prog_addr,
    input wire [ 7:0]   prog_data,
    input wire [ 1:0]   prog_mask,
    input wire          prog_we,
    output wire         downloading,
    // ROM access from game
    input  wire         sdram_req,
    output wire         sdram_ack,
    input  wire [21:0]   sdram_addr,
    output wire [31:0]   data_read,
    output wire          data_rdy,
    output wire         loop_rst,
    input  wire         refresh_en,	 
//////////// board
    output  wire        rst,      // synchronous reset
    output wire         rst_n,    // asynchronous reset
    output wire         game_rst,
    output wire         game_rst_n,
    // reset forcing signals:
    input  wire         rst_req,
    // Sound
    input  wire [15:0]  snd_left,
	 input  wire [15:0]  snd_right,
    output wire         AUDIO_L,
    output wire         AUDIO_R,
    // joystick
    output wire  [9:0]  game_joystick1,
    output wire  [9:0]  game_joystick2,
    output wire  [1:0]  game_coin,
    output wire  [1:0]  game_start,
    output wire         game_pause,
    output  wire        game_service,
    // DIP and OSD settings
    output wire         LED,
    input  wire [ 1:0]  BTN,
	 //Keyboard y Joy (Entradas)
    input wire			  PS2_CLK,
    input wire			  PS2_DATA,
	 output wire			  JOY_CLK, 
    output	wire		  JOY_LOAD,
    input  wire			  JOY_DATA,
    output wire         enable_fm,
    output wire        enable_psg,
    output wire         dip_test,
    // non standard:
    output wire        dip_pause,
    output wire        dip_flip,     // A change in dip_flip implies a reset
    output wire [ 1:0]  dip_fxlevel,
    // Debug
    output wire  [3:0]  gfx_en
);

parameter CONF_STR_LEN=4;
parameter SIGNED_SND=1'b0;
parameter THREE_BUTTONS=1'b0;
parameter GAME_INPUTS_ACTIVE_LOW=1'b1;
parameter CONF_STR = "";

// control
wire [31:0]   joystick1, joystick2;
//wire          ps2_kbd_clk, ps2_kbd_data;
//wire          osd_shown;

wire [7:0]    scan2x_r, scan2x_g, scan2x_b;
wire          scan2x_hs, scan2x_vs;
wire          scan2x_enb;
wire [3:0]    vgactrl_en;

///////////////// LED is on while
// downloading, PLL lock lost, OSD is shown or in reset state
//assign LED[0] = ~( downloading | ~pll_locked | osd_shown | rst );

assign LED = ~ downloading;
wire  [ 1:0]  rotate;


jtgng_cyclone5_base u_base(
    .rst            ( rst           ),
    .clk_sys        ( clk_sys       ),
    .clk_vga        ( clk_vga       ),
    .clk_rom        ( clk_rom       ),
    // Base video
    .osd_rotate     ( rotate        ),
    .game_r         ( game_r        ),
    .game_g         ( game_g        ),
    .game_b         ( game_b        ),
    .LHBL           ( LHBL          ),
    .LVBL           ( LVBL          ),
    .hs             ( hs            ),
    .vs             ( vs            ), 
    .pxl_cen        ( pxl_cen       ),
    // Scan-doubler video
    .scan2x_r       ( scan2x_r[7:2] ),
    .scan2x_g       ( scan2x_g[7:2] ),
    .scan2x_b       ( scan2x_b[7:2] ),
    .scan2x_hs      ( scan2x_hs     ),
    .scan2x_vs      ( scan2x_vs     ),
    .scan2x_enb     ( scan2x_enb    ),
	 .vgactrl_en     ( vgactrl_en    ),
    // MiST VGA pins (includes OSD)
    .VIDEO_R        ( VGA_R         ),
    .VIDEO_G        ( VGA_G         ),
    .VIDEO_B        ( VGA_B         ),
    .VIDEO_HS       ( VGA_HS        ),
    .VIDEO_VS       ( VGA_VS        ),
    // SPI interface to zpu io controller
    .SD_CS_N        ( SD_CS_N        ),
    .SD_CLK         ( SD_CLK         ),
    .SD_MOSI        ( SD_MOSI        ),
    .SD_MISO        ( SD_MISO        ),
	 .pll_locked     ( pll_locked     ),
    // control
    .status         ( status        ),
    // audio
    .clk_dac        ( clk_sys       ), 
	 .snd_left       ( snd_left      ),
    .snd_right      ( snd_right     ),
    .snd_pwm_l      ( AUDIO_L       ),
	 .snd_pwm_r      ( AUDIO_R       ),
    // ROM load from SPI
    .ioctl_addr     ( ioctl_addr    ),
    .ioctl_data     ( ioctl_data    ),
    .ioctl_wr       ( ioctl_wr      ),
    .downloading    ( downloading   )
);

jtframe_board u_board(
    .rst            ( rst             ),
    .rst_n          ( rst_n           ),
    .game_rst       ( game_rst        ),
    .game_rst_n     ( game_rst_n      ),
    .rst_req        ( rst_req         ),
    .downloading    ( downloading     ),

    .clk_sys        ( clk_sys         ),
    .clk_rom        ( clk_rom         ),
    .clk_vga        ( clk_vga         ),
    // joystick
    .ps2_kbd_clk    ( PS2_CLK         ), //ps2_kbd_clk     ),
    .ps2_kbd_data   ( PS2_DATA        ), //ps2_kbd_data    ),
    .JOY_CLK        ( JOY_CLK         ),
    .JOY_LOAD       ( JOY_LOAD        ),
	 .JOY_DATA       ( JOY_DATA        ),
`ifndef SIM_INPUTS
    .game_joystick1 ( game_joystick1  ),
    .game_joystick2 ( game_joystick2  ),
    .game_coin      ( game_coin       ),
    .game_start     ( game_start      ),
`endif
    .game_service   ( game_service    ),
    // DIP and OSD settings
    .status         ( status          ),
    .enable_fm      ( enable_fm       ),
    .enable_psg     ( enable_psg      ),
    .dip_test       ( dip_test        ),
    .dip_pause      ( dip_pause       ),
    .dip_flip       ( dip_flip        ),
    .dip_fxlevel    ( dip_fxlevel     ),
    // screen
    .rotate         ( rotate          ),
    // SDRAM interface
    .SDRAM_DQ       ( SDRAM_DQ        ),
    .SDRAM_A        ( SDRAM_A         ),
    .SDRAM_DQML     ( SDRAM_DQML      ),
    .SDRAM_DQMH     ( SDRAM_DQMH      ),
    .SDRAM_nWE      ( SDRAM_nWE       ),
    .SDRAM_nCAS     ( SDRAM_nCAS      ),
    .SDRAM_nRAS     ( SDRAM_nRAS      ),
    .SDRAM_nCS      ( SDRAM_nCS       ),
    .SDRAM_BA       ( SDRAM_BA        ),
    .SDRAM_CKE      ( SDRAM_CKE       ),
    // SDRAM controller
    .loop_rst       ( loop_rst        ),
    .sdram_addr     ( sdram_addr      ),
    .sdram_req      ( sdram_req       ),
    .sdram_ack      ( sdram_ack       ),
    .data_read      ( data_read       ),
    .data_rdy       ( data_rdy        ),
    .refresh_en     ( refresh_en      ),
    .prog_addr      ( prog_addr       ),
    .prog_data      ( prog_data       ),
    .prog_mask      ( prog_mask       ),
    .prog_we        ( prog_we         ),
    // Base video
    .osd_rotate     ( rotate          ),
    .game_r         ( game_r          ),
    .game_g         ( game_g          ),
    .game_b         ( game_b          ),
    .LHBL           ( LHBL            ),
    .LVBL           ( LVBL            ),
    .hs             ( hs              ),
    .vs             ( vs              ), 
    .pxl_cen        ( pxl_cen         ),
    .pxl2_cen       ( pxl2_cen        ),
    // Scan-doubler video
    .scan2x_r       ( scan2x_r        ),
    .scan2x_g       ( scan2x_g        ),
    .scan2x_b       ( scan2x_b        ),
    .scan2x_hs      ( scan2x_hs       ),
    .scan2x_vs      ( scan2x_vs       ),
    .scan2x_enb     ( scan2x_enb      ),
	 .vgactrl_en     ( vgactrl_en      ),
    // Debug
    .gfx_en         ( gfx_en          )
);

endmodule // jtframe