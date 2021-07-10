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
    Date: 12-6-2021 */



module jtframe_neptuno_joy(
    input   clk,
    input   reset,

    output  joy_clk,
    input   joy_data,
    output  joy_load,
    output  joy_select,
    
    input        ps2_kbd_clk,
    input        ps2_kbd_data,
    input  [3:0] BUTTON_n,

    output [11:0] joy1,
    output [11:0] joy2,
    
    output [7:0]  osd,
    output        mc_reset,
    output        toggle_scandb
);

wire joy1_up, joy1_down, joy1_left, joy1_right, joy1_p6, joy1_p9;
wire joy2_up, joy2_down, joy2_left, joy2_right, joy2_p6, joy2_p9;

wire [11:0] inv1, inv2;
wire [ 7:0] osd_s;
wire [ 8:0] controls_s;
wire [ 3:0] btn_n_s;

wire P1coin_s, P2coin_s, P1start_s, P2start_s;
 
// makes it active high, and sets the Mode, START, XYZ ABC button order
// MX YZS ACB = input
// MS XYZ ABC = output
// BA 987 654
//function [11:0] translate;
//    input [11:0] in;
//    translate = ~{ in[11], in[7], in[10], in[9] & btn_n_s[1], in[8] & btn_n_s[2], in[5:4], in[6], in[3:0] };
//endfunction

//assign joy1 = translate( inv1 );
//assign joy2 = translate( inv2 );

assign P1coin_s  = ~btn_n_s[2] | controls_s[4];
assign P2coin_s  = ~btn_n_s[2] | controls_s[5];
assign P1start_s = ~btn_n_s[0] | controls_s[0];
assign P2start_s = ~btn_n_s[1] | controls_s[1];

// is the coins and starts always at same position?
assign joy1 = { inv1[11], inv1[7], inv1[10], inv1[9], inv1[8] | P1coin_s, inv1[5] | P1start_s, inv1[4], inv1[6], inv1[3:0] };
assign joy2 = { inv2[11], inv2[7], inv2[10], inv2[9], inv2[8] | P2coin_s, inv2[5] | P2start_s, inv2[4], inv2[6], inv2[3:0] };

assign osd = osd_s;
assign mc_reset = ~btn_n_s[3];

joystick_serial u_serial(
    .clk_i           ( clk        ),
    .joy_data_i      ( joy_data   ),
    .joy_clk_o       ( joy_clk    ),
    .joy_load_o      ( joy_load   ),

    .joy1_up_o       ( joy1_up    ),
    .joy1_down_o     ( joy1_down  ),
    .joy1_left_o     ( joy1_left  ),
    .joy1_right_o    ( joy1_right ),
    .joy1_fire1_o    ( joy1_p6    ),
    .joy1_fire2_o    ( joy1_p9    ),

    .joy2_up_o       ( joy2_up    ),
    .joy2_down_o     ( joy2_down  ),
    .joy2_left_o     ( joy2_left  ),
    .joy2_right_o    ( joy2_right ),
    .joy2_fire1_o    ( joy2_p6    ),
    .joy2_fire2_o    ( joy2_p9    )
);

/*
joystick_sega #(48000) u_sega(
    .clk_i         ( clk        ),
    .joy0_i        ({ joy1_p9, joy1_p6, joy1_up, joy1_down, joy1_left, joy1_right }),
    .joy1_i        ({ joy2_p9, joy2_p6, joy2_up, joy2_down, joy2_left, joy2_right }),

    .player1_o     ( inv1       ),
    .player2_o     ( inv2       ),
    .sega_strobe_o ( joy_select )
);*/


`ifdef JTFRAME_CLK96 
    `define CLK_SPEED 96000
`else
    `define CLK_SPEED 48000
`endif

MC2_HID #( .CLK_SPEED( `CLK_SPEED ) ) k_hid
(
    .clk_i          ( clk          ),
    .reset_i        ( reset        ),
    .kbd_clk_i      ( ps2_kbd_clk  ),
    .kbd_dat_i      ( ps2_kbd_data ),
    
    .joystick_0_i   ({ joy1_p9, joy1_p6, joy1_up, joy1_down, joy1_left, joy1_right }),
    .joystick_1_i   ({ joy2_p9, joy2_p6, joy2_up, joy2_down, joy2_left, joy2_right }),
      
    //-- tilt, coin4-1, start4-1
    .controls_o     ( controls_s ),

    //-- fire12-1, up, down, left, right

    .player1_o      ( inv1 ),
    .player2_o      ( inv2 ),

    //-- keys to the OSD
    .osd_o          ( osd_s ),
    .osd_enable_i   ( 1'b1 ), //osd_enable ), //ideally we should know when the OSD is open
    
    .toggle_scandb_o ( toggle_scandb ),
    
    //-- sega joystick
    .sega_strobe_o  ( joy_select ),

    //-- Front buttons
    .front_buttons_i ( BUTTON_n ),
    .front_buttons_o ( btn_n_s  )        
);

endmodule
