/*  This file is part of JT_FRAME.
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
    Date: 25-9-2019 */

module jtframe_board #(parameter
    THREE_BUTTONS           = 0,
    GAME_INPUTS_ACTIVE_LOW  = 1'b1,
    COLORW                  = 4,
    VIDEO_WIDTH             = 384,
    VIDEO_HEIGHT            = 224
)(
    output  reg       rst=1'b0,      // use as synchrnous reset
    output  reg       rst_n=1'b1,    // use as asynchronous reset
    output  reg       game_rst=1'b0,
    output  reg       game_rst_n=1'b1,
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
    input             prog_rd,
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
    input     [15:0]  board_joystick1,
    input     [15:0]  board_joystick2,
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
    input [COLORW-1:0] game_r,
    input [COLORW-1:0] game_g,
    input [COLORW-1:0] game_b,
    input             LHBL,
    input             LVBL,
    input             hs,
    input             vs, 
    input             pxl_cen,
    input             pxl2_cen,
    // HDMI outputs (only for MiSTer)
    inout     [21:0]  gamma_bus,
    input             direct_video,
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

wire  [ 2:0]  scanlines;
wire          en_mixing;
wire          scandoubler = ~scan2x_enb;


wire invert_inputs = GAME_INPUTS_ACTIVE_LOW;
wire key_reset, key_pause, rot_control;
reg [7:0] rst_cnt=8'd0;
reg       game_pause;

`ifdef JTFRAME_MISTER_VIDEO_DW
localparam arcade_fx_dw = `JTFRAME_MISTER_VIDEO_DW;
`else 
localparam arcade_fx_dw = COLORW*3;
`endif

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
    else if( game_rst_cnt != ~8'b0 ) begin
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
wire [3:0] key_vgactrl;
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
    joy1_sync <= board_joystick1;
    joy2_sync <= board_joystick2;
end

localparam START1_BIT = 6+THREE_BUTTONS;
localparam START2_BIT = 7+THREE_BUTTONS;
localparam COIN_BIT   = 8+THREE_BUTTONS;
localparam PAUSE_BIT  = 9+THREE_BUTTONS;

reg last_pause, last_joypause, last_reset;
reg [3:0] last_gfx;
reg [3:0] last_vgactrl;
wire joy_pause = joy1_sync[PAUSE_BIT] | joy2_sync[PAUSE_BIT];

integer cnt;

function [9:0] apply_rotation;
    input [9:0] joy_in;
    input       rot;
    input       invert;
    begin
    apply_rotation = {10{invert}} ^ 
        (!rot ? joy_in : { joy_in[9:4], joy_in[0], joy_in[1], joy_in[3], joy_in[2] });
    end
endfunction

`ifdef SIM_INPUTS
    reg [15:0] sim_inputs[0:16383];
    integer frame_cnt;
    initial begin : read_sim_inputs
        integer c;
        for( c=0; c<16384; c=c+1 ) sim_inputs[c] = 8'h0;
        $display("INFO: input simulation enabled");
        $readmemh( "sim_inputs.hex", sim_inputs );
    end
    always @(negedge LVBL, posedge rst) begin
        if( rst )
            frame_cnt <= 0;
        else frame_cnt <= frame_cnt+1;
    end
`endif

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
        
        `ifdef SIM_INPUTS
        game_coin  = {2{invert_inputs}} ^ sim_inputs[frame_cnt][1:0];
        game_start = {2{invert_inputs}} ^ sim_inputs[frame_cnt][3:2];
        game_joystick1 <= {10{invert_inputs}} ^ { 4'd0, sim_inputs[frame_cnt][9:4]};
        `else
        game_joystick1 <= apply_rotation(joy1_sync | key_joy1, rot_control, invert_inputs);
        game_coin      <= {2{invert_inputs}} ^ 
            ({joy2_sync[COIN_BIT],joy1_sync[COIN_BIT]} | key_coin);
        
        game_start     <= {2{invert_inputs}} ^ 
            ({joy1_sync[START2_BIT],joy1_sync[START1_BIT]} |
             {joy2_sync[START2_BIT],joy2_sync[START1_BIT]} | key_start);
        `endif
        game_joystick2 <= apply_rotation(joy2_sync | key_joy2, rot_control, invert_inputs);

        soft_rst <= key_reset && !last_reset;

        for(cnt=0; cnt<4; cnt=cnt+1)
            if( key_gfx[cnt] && !last_gfx[cnt] ) gfx_en[cnt] <= ~gfx_en[cnt];
	   if( key_vgactrl[0] && !last_vgactrl[0] ) vgactrl_en[0] <= ~vgactrl_en[0];
	   if( key_vgactrl[1] && !last_vgactrl[1] ) vgactrl_en[1] <= ~vgactrl_en[1];
		if( key_vgactrl[2] && !last_vgactrl[2] ) vgactrl_en[2] <= ~vgactrl_en[2];
		if( key_vgactrl[3] && !last_vgactrl[3] ) vgactrl_en[3] <= ~vgactrl_en[3];

		// state variables:
        `ifndef DIP_PAUSE
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

// This strange arrangement is what MiSTer 128MB board needs:
wire [12:11] sdram_a;
wire         sdram_dqml, sdram_dqmh;

assign       SDRAM_DQML = sdram_a[11] | sdram_dqml;
assign       SDRAM_DQMH = sdram_a[12] | sdram_dqmh;
assign       SDRAM_A[11] = SDRAM_DQML;
assign       SDRAM_A[12] = SDRAM_DQMH;

jtframe_sdram u_sdram(
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
    .prog_rd        ( prog_rd       ),
    .prog_addr      ( prog_addr     ),
    .prog_data      ( prog_data     ),
    .prog_mask      ( prog_mask     ),
    .sdram_addr     ( sdram_addr    ),
    .sdram_ack      ( sdram_ack     ),
    // SDRAM interface
    .SDRAM_DQ       ( SDRAM_DQ      ),
    .SDRAM_A        ( { sdram_a, SDRAM_A[10:0] } ),
    .SDRAM_DQML     ( sdram_dqml    ),
    .SDRAM_DQMH     ( sdram_dqmh    ),
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

localparam SCAN2X_TYPE=`SCAN2X_TYPE;

`ifdef SIMULATION
initial $display("INFO: Scan 2x type =%d", SCAN2X_TYPE);
`endif

wire [COLORW*3-1:0] game_rgb = {game_r, game_g, game_b };

function [7:0] extend8;
    input [COLORW-1:0] a;
    case( COLORW )
        3: extend8 = { a, a, a[2:1] };
        4: extend8 = { a, a         };
        5: extend8 = { a, a[4:2]    };
        6: extend8 = { a, a[5:4]    };
        7: extend8 = { a, a[6]      };
        8: extend8 = a;
    endcase
endfunction

function [7:0] extend8b;    // the input width is COLORW+1
    input [COLORW:0] a;
    case( COLORW )
        3: extend8b = { a, a         };
        4: extend8b = { a, a[4:2]    };
        5: extend8b = { a, a[5:4]    };
        6: extend8b = { a, a[6]      };
        7: extend8b = a;
        8: extend8b = a[8:1];
    endcase
endfunction

generate    
    if( ROTATE_FX ) begin
        wire hblank = ~LHBL;
        wire vblank = ~LVBL;

        arcade_rotate_fx #(.WIDTH(VIDEO_WIDTH),.HEIGHT(VIDEO_HEIGHT),.DW(COLORW*3),.CCW(1)) 
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
            .gamma_bus  ( gamma_bus     ),

        
            .fx                ( scanlines   ),
            .forced_scandoubler( ~scan2x_enb ),
            .direct_video      ( direct_video),
            .no_rotate         ( rotate[0]   ) // the no_rotate name
                // is misleading. A low value in no_rotate will actually
                // rotate the game video. If the game is vertical, a low value
                // presents the game correctly on a horizontal screen
        );
    end
    else case( SCAN2X_TYPE )
        default: begin // JTFRAME easy going scaler
            wire [COLORW*3-1:0] rgbx2;

            jtframe_scan2x #(.DW(COLORW*3), .HLEN(VIDEO_WIDTH)) u_scan2x(
                .rst_n      ( rst_n        ),
                .clk        ( clk_sys      ),
                .base_cen   ( pxl_cen      ),
                .basex2_cen ( pxl2_cen     ),
                .base_pxl   ( game_rgb     ),
                .x2_pxl     ( rgbx2        ),
                .HS         ( hs           ),
                .scanlines  ( scanlines[0] ),					
                .x2_HS      ( scan2x_hs    )
            );
            assign scan2x_vs = vs;
            assign scan2x_r     = extend8( rgbx2[COLORW*3-1:COLORW*2] );
            assign scan2x_g     = extend8( rgbx2[COLORW*2-1:COLORW] );
            assign scan2x_b     = extend8( rgbx2[COLORW-1:0] );
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
            // Do not use this scaler with MiSTer
            wire [COLORW:0] pre_r, pre_g, pre_b;
            wire pre_hb, pre_vb;

            jtgng_vga #(COLORW) u_gngvga (
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
                .vga_hsync  ( scan2x_hs     ),
                .vga_vsync  ( scan2x_vs     ),
                .vga_vb     ( pre_vb        ),
                .vga_hb     ( pre_hb        )
            );
            assign scan2x_r      = extend8b( pre_r );
            assign scan2x_g      = extend8b( pre_g );
            assign scan2x_b      = extend8b( pre_b );
            assign scan2x_de     = !pre_vb && !pre_hb;
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
            localparam HALF_DEPTH = COLORW==4;
            wire [ (HALF_DEPTH?3:7):0 ] mr_mixer_r = extend8( game_r );
            wire [ (HALF_DEPTH?3:7):0 ] mr_mixer_g = extend8( game_g );
            wire [ (HALF_DEPTH?3:7):0 ] mr_mixer_b = extend8( game_b );
            wire mixer_ce = pxl_cen | (~scandoubler & ~gamma_bus[19] & ~direct_video);
            video_mixer #(
                .LINE_LENGTH(VIDEO_WIDTH+4),
                .HALF_DEPTH(HALF_DEPTH)) 
            u_video_mixer (
                .clk_vid        ( clk_sys       ),
                .ce_pix         ( pxl_cen       ),
                .ce_pix_out     ( scan2x_cen    ),
                .scandoubler    ( scandoubler   ),        
                .scanlines      ( sl            ),
                .hq2x           ( hq2x_en       ),
                .R              ( mr_mixer_r    ),
                .G              ( mr_mixer_g    ),
                .B              ( mr_mixer_b    ),
                .mono           ( 1'b0          ),
                .gamma_bus      ( gamma_bus     ),
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
        3: begin // MiSTer cleaner, use for interlaced games
            wire [1:0] nc_r, nc_g, nc_b;
            localparam HALF_DEPTH = COLORW==4;
            wire [ (HALF_DEPTH?3:7):0 ] mr_mixer_r = extend8( game_r );
            wire [ (HALF_DEPTH?3:7):0 ] mr_mixer_g = extend8( game_g );
            wire [ (HALF_DEPTH?3:7):0 ] mr_mixer_b = extend8( game_b );
            video_cleaner u_cleaner (
                .clk_vid    ( clk_sys    ),
                .ce_pix     ( pxl2_cen   ),

                .R          ( mr_mixer_r ),
                .G          ( mr_mixer_g ),
                .B          ( mr_mixer_b ),

                .HSync      ( hs         ),
                .VSync      ( vs         ),
                .HBlank     ( ~LHBL      ),
                .VBlank     ( ~LVBL      ),

                // video output signals
                .VGA_R      ( scan2x_r   ),
                .VGA_G      ( scan2x_g   ),
                .VGA_B      ( scan2x_b   ),
                .VGA_HS     ( scan2x_hs  ),
                .VGA_VS     ( scan2x_vs  ),
                .VGA_DE     ( scan2x_de  ),
                
                // optional aligned blank
                .HBlank_out (            ),
                .VBlank_out (            )
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
            assign hdmi_sl    = 2'b0;
        end
        4: begin // MiSTer arcade_fx
            arcade_fx #(.WIDTH(VIDEO_WIDTH),.DW(arcade_fx_dw)) u_fx(
                .clk_video      ( clk_sys       ),
                .ce_pix         ( pxl_cen       ),

                .RGB_in         ( {game_r, game_g, game_b } ),
                .HSync          ( hs            ),
                .VSync          ( vs            ),
                .HBlank         ( ~LHBL         ),
                .VBlank         ( ~LVBL         ),

                .VGA_CLK        ( scan2x_clk    ),
                .VGA_CE         ( scan2x_cen    ),
                .VGA_R          ( scan2x_r      ),
                .VGA_G          ( scan2x_g      ),
                .VGA_B          ( scan2x_b      ),
                .VGA_HS         ( scan2x_hs     ),
                .VGA_VS         ( scan2x_vs     ),
                .VGA_DE         ( scan2x_de     ),

                .HDMI_CLK       ( hdmi_clk      ),
                .HDMI_CE        ( hdmi_cen      ),
                .HDMI_R         ( hdmi_r        ),
                .HDMI_G         ( hdmi_g        ),
                .HDMI_B         ( hdmi_b        ),
                .HDMI_HS        ( hdmi_hs       ),
                .HDMI_VS        ( hdmi_vs       ),
                .HDMI_DE        ( hdmi_de       ),
                .HDMI_SL        ( hdmi_sl       ),

                .fx             ( scanlines     ),
                .forced_scandoubler( scandoubler),
                .gamma_bus      ( gamma_bus     )
            );
        end
    endcase
endgenerate

endmodule // jtgng_board