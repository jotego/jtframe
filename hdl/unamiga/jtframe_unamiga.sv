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

module jtframe_unamiga #(parameter
    SIGNED_SND             = 1'b0,
    THREE_BUTTONS          = 1'b0,
    GAME_INPUTS_ACTIVE_LOW = 1'b1,
    CONF_STR               = "",
    COLORW                 = 4,
    VIDEO_WIDTH            = 384,
    VIDEO_HEIGHT           = 224
)(
    input           clk_sys,
    input           clk_rom,
    input           clk_vga,
    input           pll_locked,
    // interface with microcontroller
    output  [31:0]  status,
    // Base video
    input [COLORW-1:0] game_r,
    input [COLORW-1:0] game_g,
    input [COLORW-1:0] game_b,
    input           LHBL,
    input           LVBL,
    input           hs,
    input           vs,
    input           pxl_cen,
    input           pxl2_cen,
    // MiST VGA pins
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
    input           SDRAM_CLK,      // SDRAM Clock
    output          SDRAM_CKE,      // SDRAM Clock Enable
    // ROM access from game
    input           sdram_req,
    output          sdram_ack,
    input  [21:0]   sdram_addr,
    output [31:0]   data_read,
    output          data_rdy,
    output          loop_rst,
    input           refresh_en,
    // SPI interface to arm io controller
    output wire         SD_CS_N,
	output wire         SD_CLK,
	output wire         SD_MOSI,
    input   wire        SD_MISO,
    // ROM load from SPI
    output [21:0]   ioctl_addr,
    output [ 7:0]   ioctl_data,
    output          ioctl_wr,
    input  [21:0]   prog_addr,
    input  [ 7:0]   prog_data,
    input  [ 1:0]   prog_mask,
    input           prog_we,
    input           prog_rd,
    output          downloading,
    input           dwnld_busy,
//////////// board
    output          rst,      // synchronous reset
    output          rst_n,    // asynchronous reset
    output          game_rst,
    output          game_rst_n,
    // reset forcing signals:
    input           rst_req,
    // Sound
    input   [15:0]  snd_left,
    input   [15:0]  snd_right,
    output          AUDIO_L,
    output          AUDIO_R,
    // joystick
    output   [9:0]  game_joystick1,
    output   [9:0]  game_joystick2,
    output   [1:0]  game_coin,
    output   [1:0]  game_start,
    output          game_pause,
    output          game_service,
    // DIP and OSD settings
    output  [ 7:0]  hdmi_arx,
    output  [ 7:0]  hdmi_ary,
    output          vertical_n,
	
    output          enable_fm,
    output          enable_psg,
	
    output          dip_test,
    // non standard:
    output          dip_pause,
    output          dip_flip,     // A change in dip_flip implies a reset
    output  [ 1:0]  dip_fxlevel,
	 //Keyboard y Joy (Entradas)
    input wire			  PS2_CLK,
    input wire			  PS2_DATA,
    input  wire	   [5:0]  JOYA,
	input  wire	   [5:0]  JOYB,
    // Debug
	input  wire [ 1:0]  BTN,
    output          LED,
    output   [3:0]  gfx_en
);

// control
wire [31:0]   joystick1, joystick2;
wire          ps2_kbd_clk, ps2_kbd_data;
wire          osd_shown;

wire [7:0]    scan2x_r, scan2x_g, scan2x_b;
wire          scan2x_hs, scan2x_vs;
wire          scan2x_enb;
wire [3:0]    vgactrl_en;

///////////////// LED is on while
// downloading, PLL lock lost, OSD is shown or in reset state
assign LED = downloading; //~( downloading | dwnld_busy | ~pll_locked | osd_shown | rst );
wire  [ 1:0]  rotate;


jtframe_unamiga_base #(
    .CONF_STR    (CONF_STR          ),
    .CONF_STR_LEN($size(CONF_STR)/8 ),
    .SIGNED_SND  (SIGNED_SND        ),
    .COLORW      ( COLORW           )
) u_base(
    .rst            ( rst           ),
    .clk_sys        ( clk_sys       ),
    .clk_vga        ( clk_vga       ),
    .clk_rom        ( clk_rom       ),
    .SDRAM_CLK      ( SDRAM_CLK     ),
    .osd_shown      ( osd_shown     ),
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
    // SPI interface to arm io controller
    .SD_CS_N        ( SD_CS_N        ),
    .SD_CLK         ( SD_CLK         ),
    .SD_MOSI        ( SD_MOSI        ),
    .SD_MISO        ( SD_MISO        ),
	.pll_locked     ( pll_locked     ),
    // control
    .status         ( status        ),
    .joystick1      ( joystick1     ),
    .joystick2      ( joystick2     ),
    .JOYA           ( JOYA          ),
    .JOYB           ( JOYB          ),
    // audio
    .clk_dac        ( clk_sys       ),
    .snd_left       ( snd_left      ),
    .snd_right      ( snd_right     ),
    .snd_pwm_left   ( AUDIO_L       ),
    .snd_pwm_right  ( AUDIO_R       ),
    // ROM load from SPI
    .ioctl_addr     ( ioctl_addr    ),
    .ioctl_data     ( ioctl_data    ),
    .ioctl_wr       ( ioctl_wr      ),
    .downloading    ( downloading   )
);

jtframe_board #(
    .THREE_BUTTONS         ( THREE_BUTTONS         ),
    .GAME_INPUTS_ACTIVE_LOW( GAME_INPUTS_ACTIVE_LOW),
    .COLORW                ( COLORW                ),
    .VIDEO_WIDTH           ( VIDEO_WIDTH           ),
    .VIDEO_HEIGHT          ( VIDEO_HEIGHT          )
) u_board(
    .rst            ( rst             ),
    .rst_n          ( rst_n           ),
    .game_rst       ( game_rst        ),
    .game_rst_n     ( game_rst_n      ),
    .rst_req        ( rst_req         ),
    .downloading    ( dwnld_busy      ), // use busy signal from game module

    .clk_sys        ( clk_sys         ),
    .clk_rom        ( clk_rom         ),
    .clk_vga        ( clk_vga         ),
    // joystick
    .ps2_kbd_clk    ( PS2_CLK     ),
    .ps2_kbd_data   ( PS2_DATA    ),
    .board_joystick1( joystick1[15:0] ),
    .board_joystick2( joystick2[15:0] ),
    .game_joystick1 ( game_joystick1  ),
    .game_joystick2 ( game_joystick2  ),
    .game_coin      ( game_coin       ),
    .game_start     ( game_start      ),
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
    .prog_rd        ( prog_rd         ),
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
    .gfx_en         ( gfx_en          ),
    // Unused ports (MiSTer)
    .hdmi_arx       (                 ),
    .hdmi_ary       (                 ),
    .hdmi_clk       (                 ),
    .hdmi_cen       (                 ),
    .hdmi_r         (                 ),
    .hdmi_g         (                 ),
    .hdmi_b         (                 ),
    .hdmi_hs        (                 ),
    .hdmi_vs        (                 ),
    .hdmi_de        (                 ),
    .hdmi_sl        (                 ),
    .scan2x_clk     (                 ),
    .scan2x_cen     (                 ),
    .scan2x_de      (                 )	
);

endmodule // jtframe