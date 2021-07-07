//Control module for Megadrive DB9 Splitter of Antonio Villena by Aitor Pelaez (NeuroRulez)
//Based on the module written by Victor Trucco and modified by Fernando Mosquera
////////////////////////////////////////////////////////////////////////////////////

module joy_db9md (
  input  clk,
  input  [5:0] joy_in,
  output joy_mdsel,
  output joy_split,
  output [11:0] joystick1,
  output [11:0] joystick2
  );

reg [7:0]state = 8'd0;
reg joy1_6btn = 1'b0,joy2_6btn = 1'b0;
reg [11:0] joyMDdat1 = 12'hFFF,joyMDdat2 = 12'hFFF;
reg [5:0] joy1_in,joy2_in;
reg joyMDsel,joySEL = 1'b0;
reg joySplit = 1'b1;

reg [7:0] delay;
always @(negedge clk) delay<=delay+1;

always @(posedge delay[5])
begin
	joySplit <= ~joySplit;
end

always @(negedge delay[5])
begin
	if (joySplit) joy2_in <= joy_in;
	else          joy1_in <= joy_in;
end

//Gestion de Joystick
	always @(negedge delay[7])
	begin
		state <= state + 1;		
		case (state)			//-- joy_s format MXYZ SACB UDLR
			8'd0:  
				begin
					joyMDsel <=  1'b0;					
				end				
			8'd1:
				joyMDsel <=  1'b1;
			8'd2:
				begin
					joyMDdat1[5:0] <= joy1_in[5:0]; //-- CBUDLR	
					joyMDdat2[5:0] <= joy2_in[5:0]; //-- CBUDLR	
					joyMDsel <= 1'b0;
					joy1_6btn <= 1'b0; //-- Assume it's not a six-button controller
					joy2_6btn <= 1'b0; //-- Assume it's not a six-button controller
				end				
			8'd3:
				begin // Si derecha e Izda es 0 es un mando de megadrive
					if (joy1_in[1:0] == 2'b00) joyMDdat1[7:6] <= joy1_in[5:4]; //-- Start, A
					else  					      joyMDdat1[7:4] <= { 1'b1, 1'b1, joy1_in[5:4] }; //-- read A/B as master System							
					if (joy2_in[1:0] == 2'b00) joyMDdat2[7:6] <= joy2_in[5:4]; //-- Start, A
					else  					      joyMDdat2[7:4] <= { 1'b1, 1'b1, joy2_in[5:4] }; //-- read A/B as master System							
					joyMDsel <= 1'b1;
				end					
			8'd4:  
				joyMDsel <= 1'b0;
			8'd5:
				begin
					if (joy1_in[3:0] == 4'b000) joy1_6btn <= 1'b1; // --it's a six button
					if (joy2_in[3:0] == 4'b000) joy2_6btn <= 1'b1; // --it's a six button
					joyMDsel <= 1'b1;
				end		
			8'd6:
				begin
					if (joy1_6btn == 1'b1) joyMDdat1[11:8] <= joy1_in[4:0]; //-- Mode, X, Y e Z
					if (joy2_6btn == 1'b1) joyMDdat2[11:8] <= joy2_in[4:0]; //-- Mode, X, Y e Z
					joyMDsel <= 1'b0;
				end 
			default:
				joyMDsel <= 1'b1;					
		endcase

	end

//joyMDdat1 y joyMDdat2	
//   11 1098 7654 3210   
//----Z  YXM SACB UDLR
//SALIDA joystick[11:0]:
//BA9876543210
//MSZYXCBAUDLR	
assign joystick1 = ~{joyMDdat1[8],joyMDdat1[7],joyMDdat1[11:9],joyMDdat1[5:4],joyMDdat1[6],joyMDdat1[3:0]};
assign joystick2 = ~{joyMDdat2[8],joyMDdat2[7],joyMDdat2[11:9],joyMDdat2[5:4],joyMDdat2[6],joyMDdat2[3:0]};
assign joy_mdsel = joyMDsel;
assign joy_split = joySplit;

endmodule
