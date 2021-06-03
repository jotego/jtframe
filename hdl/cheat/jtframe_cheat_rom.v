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
    Date: 1-6-2021 */

module jtframe_cheat_rom #(parameter AW=10)(
    input           clk,
    input  [AW-1:0] iaddr,
    output   [17:0] idata,
    // PBlaze Program
    input           prog_en,      // resets the address counter
    input           prog_wr,      // strobe for new data
    input  [7:0]    prog_data
);

// 8 to 18 bit conversion
reg  [15:0] prog_fifo;
reg         last_en, prog_post;
reg  [17:0] prog_word;
reg         word_we;
reg  [ 3:0] word_cnt;
reg  [AW-1:0] prog_addr;

always @(posedge clk) begin
    last_en <= prog_en;
    if( prog_en & ~last_en ) begin
        word_cnt  <= 0;
        prog_post <= 0;
        prog_addr <= 0;
        prog_word <= 0;
    end else begin
        if( prog_wr & prog_en ) begin
            prog_fifo <= { prog_data, prog_fifo[15:8] };
            word_cnt  <= word_cnt==9 ? 4'd0 : word_cnt + 4'd1;
            case( word_cnt )
                2: begin
                    word_we   <= 1;
                    prog_word <= { prog_data[1:0], prog_fifo };
                end
                4: begin
                    word_we   <= 1;
                    prog_word <= { prog_data[3:0], prog_fifo[15:2] };
                end
                6: begin
                    word_we   <= 1;
                    prog_word <= { prog_data[5:0], prog_fifo[15:4] };
                end
                8: begin
                    word_we   <= 1;
                    prog_word <= { prog_data[7:0], prog_fifo[15:6] };
                end
                default: word_we <= 0;
            endcase
        end else begin
            word_we <= 0;
        end
        if( word_we ) prog_addr <= prog_addr+1'd1;
    end
end

jtframe_prom #(.dw(18),.aw(AW),.simhex("cheat.hex")) u_irom(
    .clk    ( clk       ),
    .cen    ( 1'b1      ),
    .data   ( prog_word ),
    .rd_addr( iaddr[AW-1:0] ),
    .wr_addr( prog_addr ),
    .we     ( word_we   ),
    .q      ( idata     )
);

endmodule
