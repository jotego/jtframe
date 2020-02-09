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
    Date: 27-10-2017 */

`timescale 1ns/1ps

module jtframe_mist_base #(parameter
    CONF_STR        = "CORE",
    CONF_STR_LEN    = 4,
    SIGNED_SND      = 1'b0,
    COLORW          = 4
) (
    input           rst,
    input           clk_sys,
    input           clk_rom,
    input           clk_vga,
    input           SDRAM_CLK,      // SDRAM Clock
    output          osd_shown,

    // Base video
    input   [1:0]   osd_rotate,
    input [COLORW-1:0] game_r,
    input [COLORW-1:0] game_g,
    input [COLORW-1:0] game_b,
    input           LHBL,
    input           LVBL,
    input           hs,
    input           vs, 
    input           pxl_cen,
    // Scan-doubler video
    input   [5:0]   scan2x_r,
    input   [5:0]   scan2x_g,
    input   [5:0]   scan2x_b,
    input           scan2x_hs,
    input           scan2x_vs,
    output          scan2x_enb, // scan doubler enable bar = scan doubler disable.
    // Final video: VGA+OSD or base+OSD depending on configuration
    output  [5:0]   VIDEO_R,
    output  [5:0]   VIDEO_G,
    output  [5:0]   VIDEO_B,
    output          VIDEO_HS,
    output          VIDEO_VS,
    // SPI interface to arm io controller
    output          SPI_DO,
    input           SPI_DI,
    input           SPI_SCK,
    input           SPI_SS2,
    input           SPI_SS3,
    input           SPI_SS4,
    input           CONF_DATA0,
    // control
    output [31:0]   status,
    output [31:0]   joystick1,
    output [31:0]   joystick2,
    output          ps2_kbd_clk,
    output          ps2_kbd_data,
    // Sound
    input           clk_dac,
    input   [15:0]  snd_left,
    input   [15:0]  snd_right,
    output          snd_pwm_left,
    output          snd_pwm_right,
    // ROM load from SPI
    output [22:0]   ioctl_addr,
    output [ 7:0]   ioctl_data,
    output          ioctl_wr,
    output          downloading
);

wire ypbpr;

`ifndef SIMULATION
    `ifndef NOSOUND

    function [19:0] snd_padded;
        input [15:0] snd;
        reg   [15:0] snd_in;
        begin
            snd_in = {snd[15]^SIGNED_SND, snd[14:0]};
            snd_padded = { 1'b0, snd_in, 3'd0 };
        end
    endfunction

    hifi_1bit_dac u_dac_left
    (
      .reset    ( rst                  ),
      .clk      ( clk_dac              ),
      .clk_ena  ( 1'b1                 ),
      .pcm_in   ( snd_padded(snd_left) ),
      .dac_out  ( snd_pwm_left         )
    );

        `ifdef STEREO_GAME
        hifi_1bit_dac u_dac_right
        (
          .reset    ( rst                  ),
          .clk      ( clk_dac              ),
          .clk_ena  ( 1'b1                 ),
          .pcm_in   ( snd_padded(snd_right)),
          .dac_out  ( snd_pwm_right        )
        );
        `else
        assign snd_pwm_right = snd_pwm_left;
        `endif
    `endif
`else // Simulation:
assign snd_pwm_left = 1'b0;
assign snd_pwm_right = 1'b0;
`endif

`ifndef SIMULATION
user_io #(.STRLEN(CONF_STR_LEN)) u_userio(
    .clk_sys        ( clk_sys   ),
    .conf_str       ( CONF_STR  ),
    .SPI_CLK        ( SPI_SCK   ),
    .SPI_SS_IO      ( CONF_DATA0),
    .SPI_MISO       ( SPI_DO    ),
    .SPI_MOSI       ( SPI_DI    ),
    .joystick_0     ( joystick2 ),
    .joystick_1     ( joystick1 ),
    .status         ( status    ),
    .ypbpr          ( ypbpr     ),
    .scandoubler_disable ( scan2x_enb ),
    // keyboard
    .ps2_kbd_clk    ( ps2_kbd_clk  ),
    .ps2_kbd_data   ( ps2_kbd_data ),
    // unused ports:
    .serial_strobe  ( 1'b0      ),
    .serial_data    ( 8'd0      ),
    .sd_lba         ( 32'd0     ),
    .sd_rd          ( 1'b0      ),
    .sd_wr          ( 1'b0      ),
    .sd_conf        ( 1'b0      ),
    .sd_sdhc        ( 1'b0      ),
    .sd_din         ( 8'd0      )
);
`else
assign joystick1 = 32'd0;
assign joystick2 = 32'd0;
assign status    = 32'd0;
assign ps2_kbd_data = 1'b0;
assign ps2_kbd_clk  = 1'b0;
`ifndef SCANDOUBLER_DISABLE
assign scan2x_enb   = 1'b0;
`define SCANDOUBLER_DISABLE 1'b0
initial $display("INFO: Use -d SCANDOUBLER_DISABLE=1 if you want video output.");
`endif
assign scan2x_enb = `SCANDOUBLER_DISABLE;
assign ypbpr = 1'b0;
`endif

data_io u_datain (
    .sck                ( SPI_SCK      ),
    .ss                 ( SPI_SS2      ),
    .sdi                ( SPI_DI       ),
    
    .rst                ( rst          ),
    .clk_sdram          ( clk_rom      ),
    .downloading_sdram  ( downloading  ),
    .ioctl_addr         ( ioctl_addr   ),
    .ioctl_data         ( ioctl_data   ),
    .ioctl_wr           ( ioctl_wr     ),
    .index              ( /* unused*/  )
);

// OSD will only get simulated if SIMULATE_OSD is defined
`ifndef SIMULATE_OSD
`ifndef SCANDOUBLER_DISABLE
`ifdef SIMULATION
`define BYPASS_OSD
`endif
`endif
`endif

`ifdef SIMINFO
initial begin
    $display("INFO: use -d SIMULATE_OSD to simulate the MiST OSD")
end
`endif


`ifndef BYPASS_OSD
// include the on screen display
wire [5:0] osd_r_o;
wire [5:0] osd_g_o;
wire [5:0] osd_b_o;
wire       HSync = scan2x_enb ? ~hs : scan2x_hs;
wire       VSync = scan2x_enb ? ~vs : scan2x_vs;
wire       CSync = ~(HSync ^ VSync);

function [5:0] extend_color;
    input [COLORW-1:0] a;
    case( COLORW )
        3: extend_color = { a, a[2:0] };
        4: extend_color = { a, a[3:2] };
        5: extend_color = { a, a[4] };
        6: extend_color = a;
        7: extend_color = a[6:1];
        8: extend_color = a[7:2];
    endcase
endfunction

wire [5:0] game_r6 = extend_color( game_r );
wire [5:0] game_g6 = extend_color( game_g );
wire [5:0] game_b6 = extend_color( game_b );

osd #(0,0,3'b110) osd (
   .clk_sys    ( scan2x_enb ? clk_sys : clk_vga ),

   // spi for OSD
   .SPI_DI     ( SPI_DI       ),
   .SPI_SCK    ( SPI_SCK      ),
   .SPI_SS3    ( SPI_SS3      ),

   .rotate     ( osd_rotate   ),

   .R_in       ( scan2x_enb ? game_r6 : scan2x_r ),
   .G_in       ( scan2x_enb ? game_g6 : scan2x_g ),
   .B_in       ( scan2x_enb ? game_b6 : scan2x_b ),
   .HSync      ( HSync        ),
   .VSync      ( VSync        ),

   .R_out      ( osd_r_o      ),
   .G_out      ( osd_g_o      ),
   .B_out      ( osd_b_o      ),

   .osd_shown  ( osd_shown    )
);

wire [5:0] Y, Pb, Pr;

rgb2ypbpr u_rgb2ypbpr
(
    .red   ( osd_r_o ),
    .green ( osd_g_o ),
    .blue  ( osd_b_o ),
    .y     ( Y       ),
    .pb    ( Pb      ),
    .pr    ( Pr      )
);

assign VIDEO_R  = ypbpr?Pr:osd_r_o;
assign VIDEO_G  = ypbpr? Y:osd_g_o;
assign VIDEO_B  = ypbpr?Pb:osd_b_o;
// a minimig vga->scart cable expects a composite sync signal on the VIDEO_HS output.
// and VCC on VIDEO_VS (to switch into rgb mode)
assign VIDEO_HS = (scan2x_enb | ypbpr) ? CSync : HSync;
assign VIDEO_VS = (scan2x_enb | ypbpr) ? 1'b1 : VSync;
`else
assign VIDEO_R  = game_r;// { game_r, game_r[3:2] };
assign VIDEO_G  = game_g;// { game_g, game_g[3:2] };
assign VIDEO_B  = game_b;// { game_b, game_b[3:2] };
assign VIDEO_HS = hs;
assign VIDEO_VS = vs;
`endif

endmodule