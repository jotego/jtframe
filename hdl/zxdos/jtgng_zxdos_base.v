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

module jtgng_zxdos_base #(parameter
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
	input wire [3:0]   vgactrl_en,	
    // Final video: VGA+OSD or base+OSD depending on configuration
    output  [5:0]   VIDEO_R,
    output  [5:0]   VIDEO_G,
    output  [5:0]   VIDEO_B,
    output          VIDEO_HS,
    output          VIDEO_VS,
    // SPI interface to arm io controller
    output wire         SD_CS_N,
	output wire         SD_CLK,
	output wire         SD_MOSI,
    input  wire         SD_MISO,
    input  wire         pll_locked,
    // control
    output [31:0]   status,
    output reg [31:0]   joystick1,
    output reg [31:0]   joystick2,
    output 			  JOY_CLK, 
    output			  JOY_LOAD,
    input 			  JOY_DATA,	 
	input  wire [1:0]   VIDEOCONF,	
    // Sound
    input           clk_dac,
    input   [15:0]  snd_left,
    input   [15:0]  snd_right,
    output          snd_pwm_left,
    output          snd_pwm_right,
    // ROM load from SPI
    output [21:0]   ioctl_addr,
    output [ 7:0]   ioctl_data,
    output          ioctl_wr,
    output          downloading
);

reg [7:0] delay_count;
wire ena_x;
 always @ (posedge clk_sys) begin
    delay_count <= delay_count + 1'b1;
 end
 assign ena_x = delay_count[7];
 reg [15:0] joy1  = 16'hFFFF, joy2  = 16'hFFFF;
 reg joy_renew = 1'b1;
 reg [4:0]joy_count = 5'd0;

 assign JOY_CLK = ena_x;
 assign JOY_LOAD = joy_renew;
 always @(posedge ena_x) begin 
		if (joy_count == 5'd0) begin
			joy_renew = 1'b0;
		end else begin
			joy_renew = 1'b1;
		end
		if (joy_count == 5'd25) begin
		  joy_count = 5'd0;
		end else begin
		  joy_count = joy_count + 1'd1;
		end		
	end
	always @(posedge ena_x) begin
		case (joy_count)
				5'd2  : joy1[8]  <= JOY_DATA; //1p Start
				5'd3  : joy1[6]  <= JOY_DATA; //1p Fuego 3
				5'd4  : joy1[5]  <= JOY_DATA; //1p Fuego 2
				5'd5  : joy1[4]  <= JOY_DATA; //1p Fuego 1
				5'd6  : joy1[0]  <= JOY_DATA; //1p Derecha
				5'd7  : joy1[1]  <= JOY_DATA; //1p Izquierda
				5'd8  : joy1[2]  <= JOY_DATA; //1p Abajo
				5'd9  : joy1[3]  <= JOY_DATA; //1p Ariba
				5'd10 : joy2[8]  <= JOY_DATA; //2p Start
				5'd11 : joy2[6]  <= JOY_DATA; //2p Fuego 3
				5'd12 : joy2[5]  <= JOY_DATA; //2p Fuego 2
				5'd13 : joy2[4]  <= JOY_DATA; //2p Fuego 1
				5'd14 : joy2[0]  <= JOY_DATA; //2p Derecha
				5'd15 : joy2[1]  <= JOY_DATA; //2p Izquierda
				5'd16 : joy2[2]  <= JOY_DATA; //2p Abajo
				5'd17 : joy2[3]  <= JOY_DATA; //2p Arriba
				5'd18 : joy2[10] <= JOY_DATA;
				5'd19 : joy2[11] <= JOY_DATA;
				5'd20 : joy2[9]  <= JOY_DATA; //2p Coin
				5'd21 : joy2[7]  <= JOY_DATA;
				5'd22 : joy1[10] <= JOY_DATA;
				5'd23 : joy1[11] <= JOY_DATA;
				5'd24 : joy1[9]  <= JOY_DATA; //1p Coin
				5'd25 : joy1[7]  <= JOY_DATA;
     endcase					
	  end

always @(posedge clk_sys) begin
`ifndef JOY_GUNSMOKE
    joystick1[15:0] <=  ~joy1;
    joystick2[15:0] <=  ~joy2;

`else //Se convierte 1 disparo mas direccion, a 3 disparos.
	joystick1[15:7] <=  ~joy1[15:7];
	joystick1[3:0]  <=  ~joy1[3:0];
	joystick1[4]    <=  ~joy1[4] &  joy1[0] & ~joy1[1]; //pulsado Fuego e Izquierda
	joystick1[5]    <=  ~joy1[4] &  joy1[0] &  joy1[1]; //Solo pulsado el fuego sin derecha ni izda
	joystick1[6]    <=  ~joy1[4] & ~joy1[0] &  joy1[1]; //pulsado Fuego y Derecha
	

	joystick2[15:7] <=  ~joy2[15:7];
	joystick2[3:0]  <=  ~joy2[3:0];
	joystick2[4]    <=  ~joy2[4] &  joy2[0] & ~joy2[1]; //pulsado Fuego e Izquierda
	joystick2[5]    <=  ~joy2[4] &  joy2[0] &  joy2[1]; //Solo pulsado el fuego sin derecha ni izda
	joystick2[6]    <=  ~joy2[4] & ~joy2[0] &  joy2[1]; //pulsado Fuego y Derecha
`endif	
end

wire ypbpr;


`ifndef DAC_SIMPLE
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
`else 

hybrid_pwm_sd dac
(
    .clk(clk_dac),
    .n_reset(~rst),
    .din(snd_left),
    .dout(snd_pwm_left)
);

assign snd_pwm_right = snd_pwm_left;
`endif	 

assign status[1:0]    = 2'b00;
assign status[2]      = 1'b0;                   //Aspect Ratio 0=Original / 1=Wide
assign status[5:3]    = {2'b00, VIDEOCONF[1] ^ vgactrl_en[1]}; //Scandoubler Fx "Solo usamos el bit de Scanlines"
assign status[6]      = vgactrl_en[3];          //Entrar al modo TEST
assign status[9:7]    = 3'd0;
assign status[11:10]  = 2'b00;           //FX volume, high, very high, very low, low
`ifdef VERTICAL_SCREEN
assign status[12]     = vgactrl_en[2];  //~vgactrl_en[2]; Dar la vuelta a la pantalla en los verticales para que que sea como la mayoria de verticales.
`else                                   //No lo voy a usar, porque algunos dados la vuelta dan gliches. Se da la vuelta a "demanda"
assign status[12]     = vgactrl_en[2];  //Mantente la pantalla sin girar en los horizontales (a no ser que pulsemos F6)
`endif
assign status[31:13]  = 19'd0;
assign scan2x_enb     = !VIDEOCONF[0] ^ vgactrl_en[0];   //0 = scandoubler disabled


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

assign VIDEO_R  = scan2x_enb ? game_r6 : scan2x_r;
assign VIDEO_G  = scan2x_enb ? game_g6 : scan2x_g;
assign VIDEO_B  = scan2x_enb ? game_b6 : scan2x_b;
// a minimig vga->scart cable expects a composite sync signal on the VIDEO_HS output.
// and VCC on VIDEO_VS (to switch into rgb mode)
assign VIDEO_HS = scan2x_enb ? CSync : HSync;
assign VIDEO_VS = scan2x_enb ? 1'b1  : VSync;

endmodule // jtgng_mist_base