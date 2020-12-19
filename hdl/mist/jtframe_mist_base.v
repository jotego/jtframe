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

module jtframe_mist_base #(parameter
    CONF_STR        = "CORE",
    CONF_STR_LEN    = 4,
    SIGNED_SND      = 1'b0,
    COLORW          = 4
) (
    input           rst,
    input           clk_sys,
    input           clk_rom,
    output          osd_shown,
    output  [6:0]   core_mod,
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
    input           scan2x_clk,
    // Final video: VGA+OSD or base+OSD depending on configuration
    output  [5:0]   VIDEO_R,
    output  [5:0]   VIDEO_G,
    output  [5:0]   VIDEO_B,
    output          VIDEO_HS,
    output          VIDEO_VS,
    // SPI interface to arm io controller
    inout           SPI_DO,
    input           SPI_DI,
    input           SPI_SCK,
    input           SPI_SS2,
    input           SPI_SS3,
    input           SPI_SS4,
    input           CONF_DATA0,
    // control
    output [63:0]   status,
    output [31:0]   joystick1,
    output [31:0]   joystick2,
    output [31:0]   joystick3,
    output [31:0]   joystick4,
    output [15:0]   joystick_analog_0,
    output [15:0]   joystick_analog_1,
    output          ps2_kbd_clk,
    output          ps2_kbd_data,
    // Sound
    input           clk_dac,
    input   [15:0]  snd_left,
    input   [15:0]  snd_right,
    output          snd_pwm_left,
    output          snd_pwm_right,
    // ROM load from SPI
    output [24:0]   ioctl_addr,
    output [ 7:0]   ioctl_data,
    input  [ 7:0]   ioctl_data_out,
    output          ioctl_wr,
    output          ioctl_ram,
    output          downloading
);

wire        ypbpr;
wire [7:0]  ioctl_index;
wire        ioctl_download;

assign downloading = ioctl_download;
assign ioctl_ram = ioctl_index == 8'hFF;

`ifndef SIMULATION
    `ifndef NOSOUND
    wire cen_dac;
    reg [3:0] cen_dac_sr;

    assign cen_dac = cen_dac_sr[0];
    always @(posedge clk_dac, posedge rst) begin
        if( rst )
            cen_dac_sr <= 4'b100;
        else begin
            cen_dac_sr <= { cen_dac_sr[2:0], cen_dac_sr[3] };
        end
    end

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
      .clk_ena  ( cen_dac              ),
      .pcm_in   ( snd_padded(snd_left) ),
      .dac_out  ( snd_pwm_left         )
    );

        `ifdef STEREO_GAME
        hifi_1bit_dac u_dac_right
        (
          .reset    ( rst                  ),
          .clk      ( clk_dac              ),
          .clk_ena  ( cen_dac              ),
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

`ifndef JTFRAME_MIST_DIRECT
`define JTFRAME_MIST_DIRECT 1'b1
`endif

`ifndef SIMULATION
user_io #(.STRLEN(CONF_STR_LEN), .ROM_DIRECT_UPLOAD(`JTFRAME_MIST_DIRECT)) u_userio(
    .rst            ( rst       ),
    .clk_sys        ( clk_sys   ),
    .conf_str       ( CONF_STR  ),
    .SPI_CLK        ( SPI_SCK   ),
    .SPI_SS_IO      ( CONF_DATA0),
    .SPI_MISO       ( SPI_DO    ),
    .SPI_MOSI       ( SPI_DI    ),
    .joystick_0     ( joystick2 ),
    .joystick_1     ( joystick1 ),
    .joystick_3     ( joystick3 ),
    .joystick_4     ( joystick4 ),
    // Analog joysticks
    .joystick_analog_0  ( joystick_analog_0 ),
    .joystick_analog_1  ( joystick_analog_1 ),

    .status         ( status    ),
    .ypbpr          ( ypbpr     ),
    .scandoubler_disable ( scan2x_enb ),
    // keyboard
    .ps2_kbd_clk    ( ps2_kbd_clk  ),
    .ps2_kbd_data   ( ps2_kbd_data ),
    // Core variant
    .core_mod       ( core_mod  ),
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
assign joystick3 = 32'd0;
assign joystick4 = 32'd0;
assign status    = 63'd0;
assign ps2_kbd_data = 1'b0;
assign ps2_kbd_clk  = 1'b0;
`ifndef SCANDOUBLER_DISABLE
    `define SCANDOUBLER_DISABLE 1'b1
    initial $display("INFO: Use -d SCANDOUBLER_DISABLE=0 if you want video output.");
`endif
initial $display("INFO:SCANDOUBLER_DISABLE=%d",`SCANDOUBLER_DISABLE);
assign scan2x_enb = `SCANDOUBLER_DISABLE;
assign ypbpr = 1'b0;
`endif

data_io #(.ROM_DIRECT_UPLOAD(1'b1)) u_datain (
    .SPI_SCK            ( SPI_SCK           ),
    .SPI_SS2            ( SPI_SS2           ),
    .SPI_SS4            ( SPI_SS4           ),
    .SPI_DI             ( SPI_DI            ),
    .SPI_DO             ( SPI_DO            ),

    .clk_sys            ( clk_rom           ),
    .clkref_n           ( 1'b0              ), // this is not a clock.
    .ioctl_download     ( ioctl_download    ),
    .ioctl_addr         ( ioctl_addr        ),
    .ioctl_dout         ( ioctl_data        ),
    .ioctl_din          ( ioctl_data_out    ),
    .ioctl_wr           ( ioctl_wr          ),
    .ioctl_index        ( ioctl_index       ),
    // Unused:
    .ioctl_fileext      (                   ),
    .ioctl_filesize     (                   )
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
wire       HSync_osd, VSync_osd;
wire       CSync_osd = ~(HSync_osd ^ VSync_osd);

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


osd #(0,0,6'b01_11_01) osd (
   .clk_sys    ( scan2x_enb ? clk_sys : scan2x_clk ),

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
   .HSync_out  ( HSync_osd    ),
   .VSync_out  ( VSync_osd    ),

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
assign VIDEO_HS = (scan2x_enb | ypbpr) ? CSync_osd : HSync_osd;
assign VIDEO_VS = (scan2x_enb | ypbpr) ? 1'b1 : VSync_osd;
`else
// for simulation only:
assign VIDEO_R  = game_r;
assign VIDEO_G  = game_g;
assign VIDEO_B  = game_b;
assign VIDEO_HS = hs;
assign VIDEO_VS = vs;
`endif

endmodule