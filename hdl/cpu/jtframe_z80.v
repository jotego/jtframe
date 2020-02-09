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
      Date: 24-4-2019 

      Originally based on a file from:
          Milkymist VJ SoC, Sebastien Bourdeauducq and Das Labor
*/

// This is a wrapper to select the right Z80
// depending on whether we are running simulations
// or synthesis

// By default use tv80s for simulation only.
// This can be overridden by defining VHDLZ80 or TV80S explicitly
`ifndef VHDLZ80
`ifndef TV80S

`ifdef SIMULATION
      `define TV80S
`else
      `define VHDLZ80
`endif

`endif
`endif

module jtframe_sysz80(
    input         rst_n,
    input         clk,
    input         cen,
    output        cpu_cen,
    input         int_n,
    input         nmi_n,
    input         busrq_n,
    output        m1_n,
    output        mreq_n,
    output        iorq_n,
    output        rd_n,
    output        wr_n,
    output        rfsh_n,
    output        halt_n,
    output        busak_n,
    output [15:0] A,
    input  [7:0]  cpu_din,
    output [7:0]  cpu_dout,
    output [7:0]  ram_dout,
    // ROM access
    input         ram_cs,
    input         rom_cs,
    input         rom_ok
);

    parameter RAM_AW=12;
    wire ram_we = ram_cs & ~wr_n;

    jtframe_ram #(.aw(RAM_AW)) u_ram(
        .clk    ( clk         ),
        .cen    ( cpu_cen     ),
        .data   ( cpu_dout    ),
        .addr   ( A[RAM_AW-1:0]),
        .we     ( ram_we      ),
        .q      ( ram_dout    )
    );


    jtframe_z80_wait u_z80wait(
        .rst_n      ( rst_n     ),
        .clk        ( clk       ),
        .cen        ( cen       ),
        .cpu_cen    ( cpu_cen   ),
        .int_n      ( int_n     ),
        .nmi_n      ( nmi_n     ),
        .busrq_n    ( busrq_n   ),
        .m1_n       ( m1_n      ),
        .mreq_n     ( mreq_n    ),
        .iorq_n     ( iorq_n    ),
        .rd_n       ( rd_n      ),
        .wr_n       ( wr_n      ),
        .rfsh_n     ( rfsh_n    ),
        .halt_n     ( halt_n    ),
        .busak_n    ( busak_n   ),
        .A          ( A         ),
        .din        ( cpu_din   ),
        .dout       ( cpu_dout  ),
        .rom_cs     ( rom_cs    ),
        .rom_ok     ( rom_ok    )
    );

endmodule

module jtframe_z80_wait (
    input         rst_n,
    input         clk,
    input         cen,
    output        cpu_cen,
    input         int_n,
    input         nmi_n,
    input         busrq_n,
    output        m1_n,
    output        mreq_n,
    output        iorq_n,
    output        rd_n,
    output        wr_n,
    output        rfsh_n,
    output        halt_n,
    output        busak_n,
    output [15:0] A,
    input  [7:0]  din,
    output [7:0]  dout,
    // ROM access
    input         rom_cs,
    input         rom_ok
);

jtframe_rom_wait u_wait(
    .rst_n    ( rst_n     ),
    .clk      ( clk       ),
    .cen_in   ( cen       ),
    .cen_out  ( cpu_cen   ),
    .gate     (           ),
      // manage access to ROM data from SDRAM
    .rom_cs   ( rom_cs    ),
    .rom_ok   ( rom_ok    )
);

jtframe_z80 u_cpu(
    .rst_n    ( rst_n     ),
    .clk      ( clk       ),
    .cen      ( cpu_cen   ),
    .wait_n   ( 1'b1      ),
    .int_n    ( int_n     ),
    .nmi_n    ( nmi_n     ),
    .busrq_n  ( busrq_n   ),
    .m1_n     ( m1_n      ),
    .mreq_n   ( mreq_n    ),
    .iorq_n   ( iorq_n    ),
    .rd_n     ( rd_n      ),
    .wr_n     ( wr_n      ),
    .rfsh_n   ( rfsh_n    ),
    .halt_n   ( halt_n    ),
    .busak_n  ( busak_n   ),
    .A        ( A         ),
    .din      ( din       ),
    .dout     ( dout      )
);

endmodule

/////////////////////////////////////////////////////////////////////

module jtframe_z80 (
    input         rst_n,
    input         clk,
    input         cen,
    input         wait_n,
    input         int_n,
    input         nmi_n,
    input         busrq_n,
    output        m1_n,
    output        mreq_n,
    output        iorq_n,
    output        rd_n,
    output        wr_n,
    output        rfsh_n,
    output        halt_n,
    output        busak_n,
    output [15:0] A,
    input  [7:0]  din,
    output [7:0]  dout
);

/* verilator tracing_off */

`ifdef VHDLZ80
T80s u_cpu(
    .RESET_n    ( rst_n       ),
    .CLK        ( clk         ),
    .CEN        ( cen         ),
    .WAIT_n     ( wait_n      ),
    .INT_n      ( int_n       ),
    .NMI_n      ( nmi_n       ),
    .RD_n       ( rd_n        ),
    .WR_n       ( wr_n        ),
    .A          ( A           ),
    .DI         ( din         ),
    .DO         ( dout        ),
    .IORQ_n     ( iorq_n      ),
    .M1_n       ( m1_n        ),
    .MREQ_n     ( mreq_n      ),
    .BUSRQ_n    ( busrq_n     ),
    .BUSAK_n    ( busak_n     ),
    .RFSH_n     ( rfsh_n      ),
    .out0       ( 1'b0        ),
    .HALT_n     ( halt_n      )
);
`endif

`ifdef TV80S
// This CPU is used for simulation
tv80s #(.Mode(0)) u_cpu (
    .reset_n( rst_n      ),
    .clk    ( clk        ),
    .cen    ( cen        ),
    .wait_n ( wait_n     ),
    .int_n  ( int_n      ),
    .nmi_n  ( nmi_n      ),
    .rd_n   ( rd_n       ),
    .wr_n   ( wr_n       ),
    .A      ( A          ),
    .di     ( din        ),
    .dout   ( dout       ),
    .iorq_n ( iorq_n     ),
    .m1_n   ( m1_n       ),
    .mreq_n ( mreq_n     ),
    .busrq_n( busrq_n    ),
    .busak_n( busak_n    ),
    .rfsh_n ( rfsh_n     ),
    .halt_n ( halt_n     )
);
`endif
/* verilator tracing_on */

endmodule // jtframe_z80