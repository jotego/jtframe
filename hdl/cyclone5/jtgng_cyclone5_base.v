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
    Date: 27-10-2017 
	 
	 Zx-Dos port by Aitor Pelaez (Neuro)
		 
	 */

`timescale 1ns/1ps

module jtgng_cyclone5_base(
    input wire      rst,
    input wire      clk_sys,
    input wire      clk_rom,
    input wire      clk_vga,
    input wire      SDRAM_CLK,      // SDRAM Clock
    output wire         osd_shown,

    // Base video
    input wire [1:0]   osd_rotate,
    input wire [3:0]   game_r,
    input wire [3:0]   game_g,
    input wire [3:0]   game_b,
    input wire         LHBL,
    input wire         LVBL,
    input wire         hs,
    input wire         vs, 
    input wire         pxl_cen,
	 
    // Scan-doubler video
    input wire [5:0]   scan2x_r,
    input wire [5:0]   scan2x_g,
    input wire [5:0]   scan2x_b,
    input wire         scan2x_hs,
    input wire         scan2x_vs,
    output wire        scan2x_enb, // scan doubler enable bar = scan doubler disable.
	 input wire [3:0]   vgactrl_en,
    // Final video: VGA+OSD or base+OSD depending on configuration
    output wire [5:0]   VIDEO_R,
    output wire [5:0]   VIDEO_G,
    output wire [5:0]   VIDEO_B,
    output wire         VIDEO_HS,
    output wire         VIDEO_VS,
	 
    // SPI interface to arm io controller
    output wire         SD_CS_N,
	 output wire         SD_CLK,
	 output wire         SD_MOSI,
    input  wire         SD_MISO,
    input  wire         pll_locked,
	 
    // control
    output wire [31:0]   status,
	 
    // Sound
    input  wire         clk_dac,
    input  wire [15:0]  snd_left,
	 input  wire [15:0]  snd_right,
    output wire         snd_pwm_l,
	 output wire         snd_pwm_r,
    // ROM load from SPI
    output wire [21:0]   ioctl_addr,
    output wire [ 7:0]   ioctl_data,
    output wire         ioctl_wr,
    output wire         downloading
);


`ifndef SIMULATION
`ifndef NOSOUND
sigma_delta_dac #(15) dac_l
(
    .CLK(clk_dac),
    .RESET(rst),
    .DACin({~snd_left[15], snd_left[14:0]}),
    .DACout(snd_pwm_l)
);

`ifndef STEREO_GAME
assign snd_pwm_r = snd_pwm_l;
`else
sigma_delta_dac #(15) dac_r
(
    .CLK(clk_dac),
    .RESET(rst),
    .DACin({~snd_right[15], snd_right[14:0]}),
    .DACout(snd_pwm_r)
);


`endif


`endif
`else
assign snd_pwm_l = 1'b0;
assign snd_pwm_r = 1'b0;
`endif

assign status[2:0] = 3'd0; //   = 32'd0;
assign status[5:3] = vgactrl_en[3:1];
assign status[31:6] = 26'd0;
assign scan2x_enb  = vgactrl_en[0]; //1'b0; // 0 = scandoubler always enabled

reg clk_med;
always @(posedge clk_rom) begin
	clk_med <= ~clk_med;
end

data_io u_datain 
	(
		.clk            (clk_rom),
		.reset_n        (pll_locked),   //1'b1 no hace reset.
		//-- SRAM card signals
		.sram_addr_w    (ioctl_addr),
      .sram_data_w    (ioctl_data),
		.sram_we        (ioctl_wr),
		//-- SD card signals
		.spi_clk        (SD_CLK),
		.spi_mosi       (SD_MOSI),
		.spi_miso       (SD_MISO),
		.spi_cs         (SD_CS_N),
		//--ROM size & Ext
		.rom_loading    (downloading)
	);


wire       HSync = scan2x_enb ? ~hs : scan2x_hs;
wire       VSync = scan2x_enb ? ~vs : scan2x_vs;
wire       CSync = ~(HSync ^ VSync);

assign VIDEO_R  = (scan2x_enb) ? { game_r, 2'b00 } : scan2x_r[5:0];
assign VIDEO_G  = (scan2x_enb) ? { game_g, 2'b00 } : scan2x_g[5:0];
assign VIDEO_B  = (scan2x_enb) ? { game_b, 2'b00 } : scan2x_b[5:0];
// a minimig vga->scart cable expects a composite sync signal on the VIDEO_HS output.
// and VCC on VIDEO_VS (to switch into rgb mode)
assign VIDEO_HS = ( scan2x_enb ) ? CSync : HSync;
assign VIDEO_VS = ( scan2x_enb ) ? 1'b1  : VSync;

endmodule // jtgng_mist_base