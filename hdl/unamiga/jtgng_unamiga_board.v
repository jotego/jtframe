/*  This file is part of JT_FRAME.
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
    Date: 25-9-2019 */

module jtframe_board(
    output  reg       rst,      // use as synchrnous reset
    output  reg       rst_n,    // use as asynchronous reset
    output  reg       game_rst,
    output  reg       game_rst_n,
    // reset forcing signals:
    input             rst_req,
    input             clk_sys,
    input             clk_rom,
    input             clk_vga,
    // ROM access from game
    input             sdram_req,
    output            sdram_ack,
    input             refresh_en,
    input  [21:0]     sdram_addr,
    output [31:0]     data_read,
    output            data_rdy,
    output            loop_rst,
    // ROM programming
    input  [21:0]     prog_addr,
    input  [ 7:0]     prog_data,
    input  [ 1:0]     prog_mask,
    input             prog_we,
    input             downloading,
    // SDRAM interface
    inout  [15:0]     SDRAM_DQ,       // SDRAM Data bus 16 Bits
    output [12:0]     SDRAM_A,        // SDRAM Address bus 13 Bits
    output            SDRAM_DQML,     // SDRAM Low-byte Data Mask
    output            SDRAM_DQMH,     // SDRAM High-byte Data Mask
    output            SDRAM_nWE,      // SDRAM Write Enable
    output            SDRAM_nCAS,     // SDRAM Column Address Strobe
    output            SDRAM_nRAS,     // SDRAM Row Address Strobe
    output            SDRAM_nCS,      // SDRAM Chip Select
    output [1:0]      SDRAM_BA,       // SDRAM Bank Address
    output            SDRAM_CKE,      // SDRAM Clock Enable
    // keyboard
    input             ps2_kbd_clk,
    input             ps2_kbd_data,
    // joystick
    input  wire	 [5:0]   JOYA,
    input  wire	 [5:0]   JOYB,
    output reg [9:0]  game_joystick1,
    output reg [9:0]  game_joystick2,
    output reg [1:0]  game_coin,
    output reg [1:0]  game_start,
    output reg        game_service,
    // DIP and OSD settings
    input     [31:0]  status,
    output    [ 7:0]  hdmi_arx,
    output    [ 7:0]  hdmi_ary,
    output    [ 1:0]  rotate,

    output            enable_fm,
    output            enable_psg,

    output            dip_test,
    // non standard:
    output            dip_pause,
    output            dip_flip,     // A change in dip_flip implies a reset
    output    [ 1:0]  dip_fxlevel,
    // Base video
    input     [ 1:0]  osd_rotate,
    input     [ 3:0]  game_r,
    input     [ 3:0]  game_g,
    input     [ 3:0]  game_b,
    input             LHBL,
    input             LVBL,
    input             hs,
    input             vs, 
    input             pxl_cen,
    input             pxl2_cen,
    // HDMI outputs (only for MiSTer)
    output            hdmi_clk,
    output            hdmi_cen,
    output    [ 7:0]  hdmi_r,
    output    [ 7:0]  hdmi_g,
    output    [ 7:0]  hdmi_b,
    output            hdmi_hs,
    output            hdmi_vs,
    output            hdmi_de,   // = ~(VBlank | HBlank)
    output    [ 1:0]  hdmi_sl,   // scanlines fx    
    // scan doubler
    input             scan2x_enb,
    output    [7:0]   scan2x_r,
    output    [7:0]   scan2x_g,
    output    [7:0]   scan2x_b,
    output            scan2x_hs,
    output            scan2x_vs,
    output            scan2x_clk,
    output            scan2x_cen,
    output            scan2x_de,
    // GFX enable
	 output reg [3:0]  vgactrl_en,
    output reg [3:0]  gfx_en
);


parameter THREE_BUTTONS=1;
parameter GAME_INPUTS_ACTIVE_LOW=1'b1;

wire  [ 2:0]  scanlines;
wire          en_mixing;

wire invert_inputs = GAME_INPUTS_ACTIVE_LOW;
wire key_reset, key_pause, rot_control;
reg [7:0] rst_cnt=8'd0;
reg       game_pause;

always @(posedge clk_sys)
    if( rst_cnt != ~8'b0 ) begin
        rst <= 1'b1;
        rst_cnt <= rst_cnt + 8'd1;
    end else rst <= 1'b0;

// rst_n is meant to be used as an asynchronous reset
// for the clk_sys domain
reg pre_rst_n;
always @(posedge clk_sys)
    if( rst | downloading | loop_rst ) begin
        pre_rst_n <= 1'b0;
        rst_n <= 1'b0;
    end else begin
        pre_rst_n <= 1'b1;
        rst_n <= pre_rst_n;
    end

reg soft_rst;
reg last_dip_flip;
reg [7:0] game_rst_cnt=8'd0;
always @(negedge clk_sys) begin
    last_dip_flip <= dip_flip;
    if( downloading | rst | rst_req | (last_dip_flip!=dip_flip) | soft_rst ) begin
        game_rst_cnt <= 8'd0;
        game_rst     <= 1'b1;
    end
    if( game_rst_cnt != ~8'b0 ) begin
        game_rst <= 1'b1;
        game_rst_cnt <= game_rst_cnt + 8'd1;
    end else game_rst <= 1'b0;
end

// convert game_rst to game_rst_n
reg pre_game_rst_n;
always @(posedge clk_sys)
    if( game_rst ) begin
        pre_game_rst_n <= 1'b0;
        game_rst_n <= 1'b0;
    end else begin
        pre_game_rst_n <= 1'b1;
        game_rst_n <= pre_game_rst_n;
    end

wire [9:0] key_joy1, key_joy2;
wire [1:0] key_start, key_coin;
wire [3:0] key_gfx;
wire [1:0] key_vgactrl;
wire       key_service;

`ifndef SIMULATION
jtgng_keyboard u_keyboard(
    .clk         ( clk_sys       ),
    .rst         ( rst           ),
    // ps2 interface
    .ps2_clk     ( ps2_kbd_clk   ),
    .ps2_data    ( ps2_kbd_data  ),
    // decoded keys
    .key_joy1    ( key_joy1      ),
    .key_joy2    ( key_joy2      ),
    .key_start   ( key_start     ),
    .key_coin    ( key_coin      ),
    .key_reset   ( key_reset     ),
    .key_pause   ( key_pause     ),
    .key_service ( key_service   ),
	 .key_vgactrl ( key_vgactrl   ),	 
    .key_gfx     ( key_gfx       )
);
`else
assign key_joy2    = 6'h0;
assign key_joy1    = 6'h0;
assign key_start   = 2'd0;
assign key_coin    = 2'd0;
assign key_reset   = 1'b0;
assign key_pause   = 1'b0;
assign key_service = 1'b0;
`endif

reg [15:0] joy1_sync, joy2_sync;
always @(posedge clk_sys) begin
`ifndef JOY_GUNSMOKE
    joy1_sync <=  {10'h0,~JOYA[5],~JOYA[4],~JOYA[3],~JOYA[2],~JOYA[1],~JOYA[0]};
    joy2_sync <=  {10'h0,~JOYB[5],~JOYB[4],~JOYB[3],~JOYB[2],~JOYB[1],~JOYB[0]};

`else //Se convierte 1 disparo mas direccion, a 3 disparos.
	joy1_sync[15:7] <=  9'h0;
	joy1_sync[3:0]  <=  ~JOYA[3:0];
	joy1_sync[4]    <=  ~JOYA[4] &  JOYA[0] & ~JOYA[1]; //pulsado Fuego e Izquierda
	joy1_sync[5]    <=  ~JOYA[4] &  JOYA[0] &  JOYA[1]; //Solo pulsado el fuego sin derecha ni izda
	joy1_sync[6]    <=  ~JOYA[4] & ~JOYA[0] &  JOYA[1]; //pulsado Fuego y Derecha
	

	joy2_sync[15:7] <=  9'h0;
	joy2_sync[3:0]  <=  ~JOYB[3:0];
	joy2_sync[4]    <=  ~JOYB[4] &  JOYB[3] & ~JOYB[2]; //pulsado Fuego e Izquierda
	joy2_sync[5]    <=  ~JOYB[4] &  JOYB[3] &  JOYB[2]; //Solo pulsado el fuego sin derecha ni izda
	joy2_sync[6]    <=  ~JOYB[4] & ~JOYB[3] &  JOYB[2]; //pulsado Fuego y Derecha
`endif	
end

localparam START1_BIT = 6+THREE_BUTTONS;
localparam START2_BIT = 7+THREE_BUTTONS;
localparam COIN_BIT   = 8+THREE_BUTTONS;
localparam PAUSE_BIT  = 9+THREE_BUTTONS;

reg last_pause, last_joypause, last_reset;
reg [3:0] last_gfx;
reg [1:0] last_vgactrl;
wire joy_pause = joy1_sync[PAUSE_BIT] | joy2_sync[PAUSE_BIT];

integer cnt;

function [10:0] apply_rotation;
    input [10:0] joy_in;
    input       rot;
    input       invert;
    begin
    apply_rotation = {11{invert}} ^ 
        (!rot ? joy_in : { joy_in[10:4], joy_in[0], joy_in[1], joy_in[3], joy_in[2] });
    end
endfunction

always @(posedge clk_sys)
    if(rst ) begin
        game_pause   <= 1'b0;
        game_service <= 1'b0 ^ invert_inputs;
        soft_rst     <= 1'b0;
        gfx_en       <= 4'hf;
    end else begin
        last_pause   <= key_pause;
        last_reset   <= key_reset;
        last_joypause <= joy_pause; // joy is active low!
        last_gfx     <= key_gfx;
		  last_vgactrl <= key_vgactrl;		  

        // joystick, coin, start and service inputs are inverted
        // as indicated in the instance parameter
        game_joystick1 <= apply_rotation(joy1_sync | key_joy1, rot_control, invert_inputs);
        game_joystick2 <= apply_rotation(joy2_sync | key_joy2, rot_control, invert_inputs);
        
        game_coin      <= {2{invert_inputs}} ^ 
            ({joy2_sync[COIN_BIT],joy1_sync[COIN_BIT]} | key_coin);
        
        game_start     <= {2{invert_inputs}} ^ 
            ({joy1_sync[START2_BIT],joy1_sync[START1_BIT]} |
             {joy2_sync[START2_BIT],joy2_sync[START1_BIT]} | key_start);
        
        soft_rst <= key_reset && !last_reset;

        for(cnt=0; cnt<4; cnt=cnt+1)
            if( key_gfx[cnt] && !last_gfx[cnt] ) gfx_en[cnt] <= ~gfx_en[cnt];
		   if( key_vgactrl[0] && !last_vgactrl[0] ) vgactrl_en[0] <= ~vgactrl_en[0];
		   if( key_vgactrl[1] && !last_vgactrl[1] ) if(vgactrl_en[3:1]<4) vgactrl_en[3:1] <= vgactrl_en[3:1]+1'b1; else vgactrl_en[3:1] <= 3'd0;
        // state variables:
        `ifndef ALWAYS_PAUSE
        if( (key_pause && !last_pause) || (joy_pause && !last_joypause) )
            game_pause   <= ~game_pause;
        `else 
        game_pause <= 1'b1;
        `endif
        game_service <= key_service ^ invert_inputs;
    end

jtframe_dip u_dip(
    .clk        ( clk_sys       ),
    .status     ( status        ),
    .game_pause ( game_pause    ),
    .hdmi_arx   ( hdmi_arx      ),
    .hdmi_ary   ( hdmi_ary      ),
    .rotate     ( rotate        ),
    .rot_control( rot_control   ),
    .en_mixing  ( en_mixing     ),
    .scanlines  ( scanlines     ),
    .enable_fm  ( enable_fm     ),
    .enable_psg ( enable_psg    ),
    .dip_test   ( dip_test      ),
    .dip_pause  ( dip_pause     ),
    .dip_flip   ( dip_flip      ),
    .dip_fxlevel( dip_fxlevel   )
);

jtgng_sdram u_sdram(
    .rst            ( rst           ),
    .clk            ( clk_rom       ), // 96MHz = 32 * 6 MHz -> CL=2
    .loop_rst       ( loop_rst      ),
    .read_req       ( sdram_req     ),
    .data_read      ( data_read     ),
    .data_rdy       ( data_rdy      ),
    .refresh_en     ( refresh_en    ),
    // ROM-load interface
    .downloading    ( downloading   ),
    .prog_we        ( prog_we       ),
    .prog_addr      ( prog_addr     ),
    .prog_data      ( prog_data     ),
    .prog_mask      ( prog_mask     ),
    .sdram_addr     ( sdram_addr    ),
    .sdram_ack      ( sdram_ack     ),
    // SDRAM interface
    .SDRAM_DQ       ( SDRAM_DQ      ),
    .SDRAM_A        ( SDRAM_A       ),
    .SDRAM_DQML     ( SDRAM_DQML    ),
    .SDRAM_DQMH     ( SDRAM_DQMH    ),
    .SDRAM_nWE      ( SDRAM_nWE     ),
    .SDRAM_nCAS     ( SDRAM_nCAS    ),
    .SDRAM_nRAS     ( SDRAM_nRAS    ),
    .SDRAM_nCS      ( SDRAM_nCS     ),
    .SDRAM_BA       ( SDRAM_BA      ),
    .SDRAM_CKE      ( SDRAM_CKE     )
);


/////////// Scan doubler
// There are several scan doublers available
// the best quality one for CAPCOM CPS0 games is jtgng_vga
// the best one for vertical games on MiSTer is arcade_rotate_fx, which
// is selected automatically in that case
// For horizontal games, the scaler can be chosen with the SCAN2X_TYPE macro
// and overridden with a parameter.

`ifdef VERTICAL_SCREEN
    `ifdef MISTER
    localparam ROTATE_FX=1;
    `else
    localparam ROTATE_FX=0;
    `endif
`else
localparam ROTATE_FX=0;
`endif

`ifndef SCAN2X_TYPE
`define SCAN2X_TYPE 0
`endif

parameter SCAN2X_TYPE=`SCAN2X_TYPE;

wire [11:0] game_rgb = {game_r, game_g, game_b };
wire hblank = ~LHBL;
wire vblank = ~LVBL;

generate    
    if( ROTATE_FX ) begin
        arcade_rotate_fx #(.WIDTH(256),.HEIGHT(224),.DW(12),.CCW(1)) 
        u_rotate_fx(
            .clk_video  ( clk_sys       ),
            .ce_pix     ( pxl_cen       ),
        
            .RGB_in     ( game_rgb      ),
            .HBlank     ( hblank        ),
            .VBlank     ( vblank        ),
            .HSync      ( hs            ),
            .VSync      ( vs            ),
        
            .VGA_CLK    (  scan2x_clk   ),
            .VGA_CE     (  scan2x_cen   ),
            .VGA_R      (  scan2x_r     ),
            .VGA_G      (  scan2x_g     ),
            .VGA_B      (  scan2x_b     ),
            .VGA_HS     (  scan2x_hs    ),
            .VGA_VS     (  scan2x_vs    ),
            .VGA_DE     (  scan2x_de    ),
        
            .HDMI_CLK   (  hdmi_clk     ),
            .HDMI_CE    (  hdmi_cen     ),
            .HDMI_R     (  hdmi_r       ),
            .HDMI_G     (  hdmi_g       ),
            .HDMI_B     (  hdmi_b       ),
            .HDMI_HS    (  hdmi_hs      ),
            .HDMI_VS    (  hdmi_vs      ),
            .HDMI_DE    (  hdmi_de      ),
            .HDMI_SL    (  hdmi_sl      ),
        
            .fx                ( scanlines   ),
            .forced_scandoubler( ~scan2x_enb ),
            .no_rotate         ( rotate[0]   ) // the no_rotate name
                // is misleading. A low value in no_rotate will actually
                // rotate the game video. If the game is vertical, a low value
                // presents the game correctly on a horizontal screen
        );
    end
    else case( SCAN2X_TYPE )
        default: begin // JTFRAME easy going scaler
            wire [11:0] rgbx2;

            jtframe_scan2x #(.DW(12), .HLEN(9'd384)) u_scan2x(
                .rst_n      ( rst_n        ),
                .clk        ( clk_sys      ),
                .base_cen   ( pxl_cen      ),
                .basex2_cen ( pxl2_cen     ),
                .base_pxl   ( game_rgb     ),
                .x2_pxl     ( rgbx2        ),
                .HS         ( hs           ),
                .scanlines  ( scanlines[0] ),						 
                .x2_HS      ( scan2x_hs )
            );
            assign scan2x_vs = vs;
            assign scan2x_r     = {2{rgbx2[11:8]} };
            assign scan2x_g     = {2{rgbx2[ 7:4]} };
            assign scan2x_b     = {2{rgbx2[ 3:0]} };
            assign scan2x_de    = ~(scan2x_vs | scan2x_hs);
            assign scan2x_cen   = pxl2_cen;
            assign scan2x_clk   = clk_sys;
            assign hdmi_clk     = scan2x_clk;
            assign hdmi_cen     = scan2x_cen;
            assign hdmi_r       = scan2x_r;
            assign hdmi_g       = scan2x_g;
            assign hdmi_b       = scan2x_b;
            assign hdmi_de      = scan2x_de;
            assign hdmi_hs      = ~scan2x_hs;
            assign hdmi_vs      = ~scan2x_vs;
            assign hdmi_sl      = 2'b0;
        end
        1: begin // JTGNG_VGA, nicely scales up to 640x480
            wire [4:0] pre_r, pre_g, pre_b;
            wire pre_hs, pre_vs, pre_hb, pre_vb;

            jtgng_vga u_gngvga (
                .clk_rgb    ( clk_sys       ),
                .cen6       ( pxl_cen       ), //  6 MHz
                .clk_vga    ( clk_vga       ), // 25 MHz
                .rst        ( rst           ), // synchronize with game
                .red        ( game_r        ),
                .green      ( game_g        ),
                .blue       ( game_b        ),
                .LHBL       ( LHBL          ),
                .LVBL       ( LVBL          ),
                .en_mixing  ( en_mixing     ),
                .vga_red    ( pre_r         ),
                .vga_green  ( pre_g         ),
                .vga_blue   ( pre_b         ),
                .vga_hsync  ( pre_hs        ),
                .vga_vsync  ( pre_vs        )//,
                //.vga_vb     ( pre_vb        ),
                //.vga_hb     ( pre_hb        )
            );

            video_cleaner u_cleaner (
                .clk_vid    ( clk_vga    ),
                .ce_pix     ( 1'b1       ),

                .R          ( { pre_r, pre_r[4:2] } ),
                .G          ( { pre_g, pre_g[4:2] } ),
                .B          ( { pre_b, pre_b[4:2] } ),

                .HSync      ( pre_hs     ),
                .VSync      ( pre_vs     ),
                .HBlank     ( pre_hb     ),
                .VBlank     ( pre_vb     ),

                // video output signals
                .VGA_R      ( scan2x_r   ),
                .VGA_G      ( scan2x_g   ),
                .VGA_B      ( scan2x_b   ),
                .VGA_VS     ( scan2x_vs  ),
                .VGA_HS     ( scan2x_hs  ),
                .VGA_DE     ( scan2x_de  ),
                
                // optional aligned blank
                .HBlank_out (          ),
                .VBlank_out (          )
            );

            assign scan2x_cen    = 1'b1;
            assign scan2x_clk    = clk_vga;
            assign hdmi_clk      = scan2x_clk;
            assign hdmi_cen      = scan2x_cen;
            assign hdmi_r        = scan2x_r;
            assign hdmi_g        = scan2x_g;
            assign hdmi_b        = scan2x_b;
            assign hdmi_de       = scan2x_de;
            assign hdmi_hs       = scan2x_hs;
            assign hdmi_vs       = scan2x_vs;
            assign hdmi_sl       = 2'b0;
        end
        2: begin // MiSTer mixer
            wire hq2x_en = scanlines==3'd1;
            reg [1:0] sl;
            always @(posedge clk_sys)
                case( scanlines )
                    default: sl <= 2'd0;
                    3'd2:    sl <= 2'd1;
                    3'd3:    sl <= 2'd2;
                    3'd4:    sl <= 2'd3;
                endcase // scanlines
            wire [1:0] nc_r, nc_g, nc_b;
            video_mixer #(.LINE_LENGTH(256), .HALF_DEPTH(1)) u_video_mixer
            (
                .clk_sys        ( clk_sys       ),
                .ce_pix         ( pxl_cen       ),
                .ce_pix_out     ( scan2x_cen    ),
                .scandoubler    ( ~scan2x_enb   ),        
                .scanlines      ( sl            ),
                .hq2x           ( hq2x_en       ),
                .R              ( game_r        ),
                .G              ( game_g        ),
                .B              ( game_b        ),
                .mono           ( 1'b0          ),
                .HSync          ( hs            ),
                .VSync          ( vs            ),
                .HBlank         ( ~LHBL         ),
                .VBlank         ( ~LVBL         ),
                .VGA_R          ( scan2x_r      ),
                .VGA_G          ( scan2x_g      ),
                .VGA_B          ( scan2x_b      ),
                .VGA_HS         ( scan2x_hs     ),
                .VGA_VS         ( scan2x_vs     ),
                .VGA_DE         ( scan2x_de     )
            );
            assign scan2x_clk = clk_sys;
            assign hdmi_clk   = scan2x_clk;
            assign hdmi_cen   = scan2x_cen;
            assign hdmi_r     = scan2x_r;
            assign hdmi_g     = scan2x_g;
            assign hdmi_b     = scan2x_b;
            assign hdmi_de    = scan2x_de;
            assign hdmi_hs    = scan2x_hs;
            assign hdmi_vs    = scan2x_vs;
            assign hdmi_sl    = sl[1:0];
        end
    endcase
endgenerate

endmodule // jtgng_board