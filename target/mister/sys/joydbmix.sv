//Control module for Megadrive DB9 Splitter of Antonio Villena by Aitor Pelaez (NeuroRulez)
//Based on the module written by Victor Trucco and modified by Fernando Mosquera
////////////////////////////////////////////////////////////////////////////////////

module joydbmix (
  input  CLK_JOY,
  input  [2:0]  JOY_FLAG,
  input  [7:0]  USER_IN,
  output [7:0]  USER_OUT,
  output [1:0]  USER_MODE,
  output        USER_OSD,
  output        joydb_1ena,
  output        joydb_2ena,
  output [15:0] joydb_1,
  output [15:0] joydb_2
  );

wire         JOY_CLK, JOY_LOAD, JOY_SPLIT, JOY_MDSEL;
wire         JOY_DATA  = JOY_FLAG[1] ? USER_IN[5] : '1;
wire   [5:0] JOY_MDIN  = JOY_FLAG[2] ? {USER_IN[6],USER_IN[3],USER_IN[5],USER_IN[7],USER_IN[1],USER_IN[2]} : '1;
assign USER_OUT  = JOY_FLAG[1] ? {6'b111111,JOY_CLK,JOY_LOAD} : JOY_FLAG[2] ? {3'b111,JOY_SPLIT,3'b111,JOY_MDSEL} : '1;
assign USER_MODE = JOY_FLAG[2:1];
assign USER_OSD = joydb_1[10] & joydb_1[6];
assign joydb_1 = JOY_FLAG[1] ? JOYDB15_1 : JOY_FLAG[2] ? JOYDB9MD_1 : '0;
assign joydb_2 = JOY_FLAG[1] ? JOYDB15_2 : JOY_FLAG[2] ? JOYDB9MD_2 : '0;
assign joydb_1ena = |JOY_FLAG[2:1];
assign joydb_2ena = |JOY_FLAG[2:1] & JOY_FLAG[0];

reg [15:0] JOYDB9MD_1,JOYDB9MD_2;
joy_db9md joy_db9md
(
  .clk       ( CLK_JOY    ), //40-50MHz
  .joy_split ( JOY_SPLIT  ),
  .joy_mdsel ( JOY_MDSEL  ),
  .joy_in    ( JOY_MDIN   ),
  .joystick1 ( JOYDB9MD_1 ),
  .joystick2 ( JOYDB9MD_2 )	  
);

reg [15:0] JOYDB15_1,JOYDB15_2;
joy_db15 joy_db15
(
  .clk       ( CLK_JOY   ), //48MHz
  .JOY_CLK   ( JOY_CLK   ),
  .JOY_DATA  ( JOY_DATA  ),
  .JOY_LOAD  ( JOY_LOAD  ),
  .joystick1 ( JOYDB15_1 ),
  .joystick2 ( JOYDB15_2 )	  
);

endmodule
