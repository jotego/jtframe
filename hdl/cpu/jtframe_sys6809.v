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
    Date: 4-1-2020

*/

module jtframe_sys6809(
    input           rstn, 
    input           clk,
    input           cen,       // This is normally the input clock to the CPU
    output          cpu_cen,   // 1/4th of cen

    // Interrupts
    input           nIRQ,
    input           nFIRQ,
    input           nNMI,
    // Bus sharing
    input           bus_busy,
    output          waitn,
    // memory interface
    output  [15:0]  A,
    output          RnW,
    input           ram_cs,
    input           rom_cs,
    input           rom_ok,
    // Bus multiplexer is external
    output  [7:0]   ram_dout,
    output  [7:0]   cpu_dout,
    input   [7:0]   cpu_din
);

// cen generation
wire E, Q;
reg  cen_E, cen_Q;
assign cpu_cen = Q;


reg [1:0] cencnt=2'd0;

always @(posedge clk) if(cen) begin
    cencnt <=  cencnt+2'd1;
end
always @(posedge clk) begin
    cen_E  <= cencnt==2'b00 & cen;
    cen_Q  <= cencnt==2'b10 & cen;
end

// RAM
parameter RAM_AW=12;
wire ram_we = ram_cs & ~RnW;

jtframe_ram #(.aw(RAM_AW)) u_ram(
    .clk    ( clk         ),
    .cen    ( cen_Q       ), // using cpu_cen instead of cen_Q creates a wrong sprite on the screen
    .data   ( cpu_dout    ),
    .addr   ( A[RAM_AW-1:0]),
    .we     ( ram_we      ),
    .q      ( ram_dout    )
);

jtframe_dual_wait #(1) u_wait(
    .rst_n      ( rstn      ),
    .clk        ( clk       ),
    .cen_in     ( { cen_E, cen_Q }    ),
    .cen_out    ( { E,Q          }    ),
    .gate       ( waitn     ),
    // manage access to shared memory
    .dev_busy   ( bus_busy  ),
    // manage access to ROM data from SDRAM
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    )
);

// cycle accurate core
wire [111:0] RegData;

mc6809i u_cpu(
    .D       ( cpu_din ),
    .DOut    ( cpu_dout),
    .ADDR    ( A       ),
    .RnW     ( RnW     ),
    .clk     ( clk     ),
    .cen_E   ( E       ),
    .cen_Q   ( Q       ),
    .BS      (         ),
    .BA      (         ),
    .nIRQ    ( nIRQ    ),
    .nFIRQ   ( nFIRQ   ),
    .nNMI    ( nNMI    ),
    .AVMA    (         ),
    .BUSY    (         ),
    .LIC     (         ),
    .nDMABREQ( 1'b1    ),
    .nHALT   ( 1'b1    ),   
    .nRESET  ( rstn    ),
    .RegData ( RegData )
);
`ifdef SIMULATION
wire [ 7:0] reg_a  = RegData[7:0];
wire [ 7:0] reg_b  = RegData[15:8];
wire [15:0] reg_x  = RegData[31:16];
wire [15:0] reg_y  = RegData[47:32];
wire [15:0] reg_s  = RegData[63:48];
wire [15:0] reg_u  = RegData[79:64];
wire [ 7:0] reg_cc = RegData[87:80];
wire [ 7:0] reg_dp = RegData[95:88];
wire [15:0] reg_pc = RegData[111:96];
reg [95:0] last_regdata;

integer fout;
initial begin
    fout = $fopen("m6809.log","w");
end
always @(posedge rom_cs) begin
    last_regdata <= RegData[95:0];
    if( last_regdata != RegData[95:0] ) begin
        $fwrite(fout,"%X, X %X, Y %X, A %X, B %X\n",
            reg_pc, reg_x, reg_y, reg_a, reg_b);
    end
end
`endif

endmodule