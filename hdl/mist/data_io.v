//
// data_io.v
//
// data_io for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
///////////////////////////////////////////////////////////////////////

module data_io
(
	input             clk_sys,
	input             SPI_SCK,
	input             SPI_SS2,
	input             SPI_SS4,
	input             SPI_DI,
	input             SPI_DO, // yes, SPI_DO is input when SS4 active

	input             clkref_n, // assert ioctl_wr one cycle after clkref stobe (negative active)

	// ARM -> FPGA download
	output reg        ioctl_download = 0, // signal indicating an active download
	output reg  [7:0] ioctl_index,        // menu index used to upload the file
	output reg        ioctl_wr,           // strobe indicating ioctl_dout valid
	output reg [24:0] ioctl_addr,
	output reg  [7:0] ioctl_dout
);

parameter START_ADDR = 25'd0;
parameter ROM_DIRECT_UPLOAD = 0;

///////////////////////////////   DOWNLOADING   ///////////////////////////////

reg  [7:0] data_w;
reg  [7:0] data_w2  = 0;
reg        rclk   = 0;
reg        rclk2  = 0;
reg        addr_reset = 0;

reg        downloading_reg = 0;
reg  [7:0] index_reg = 0;

localparam DIO_FILE_TX      = 8'h53;
localparam DIO_FILE_TX_DAT  = 8'h54;
localparam DIO_FILE_INDEX   = 8'h55;

// data_io has its own SPI interface to the io controller
always@(posedge SPI_SCK, posedge SPI_SS2) begin
	reg  [6:0] sbuf;
	reg  [7:0] cmd;
	reg  [3:0] cnt;
	reg [24:0] addr;

	if(SPI_SS2) cnt <= 0;
	else begin
		// don't shift in last bit. It is evaluated directly
		// when writing to ram
		if(cnt != 15) sbuf <= { sbuf[5:0], SPI_DI};

		// count 0-7 8-15 8-15 ...
		if(cnt != 15) cnt <= cnt + 1'd1;
			else cnt <= 8;

		// finished command byte
		if(cnt == 7) cmd <= {sbuf, SPI_DI};

		// prepare/end transmission
		if((cmd == DIO_FILE_TX) && (cnt == 15)) begin
			// prepare
			if(SPI_DI) begin
				addr_reset <= ~addr_reset;
				downloading_reg <= 1;
			end else begin
				downloading_reg <= 0;
			end
		end

		// command 0x54: UIO_FILE_TX
		if((cmd == DIO_FILE_TX_DAT) && (cnt == 15)) begin
			data_w <= {sbuf, SPI_DI};
			rclk <= ~rclk;
		end

		// expose file (menu) index
		if((cmd == DIO_FILE_INDEX) && (cnt == 15)) index_reg <= {sbuf, SPI_DI};
	end
end


// direct SD Card->FPGA transfer
generate if (ROM_DIRECT_UPLOAD == 1) begin

always@(posedge SPI_SCK, posedge SPI_SS4) begin
	reg  [6:0] sbuf2;
	reg  [2:0] cnt2;
	reg  [9:0] bytecnt;

	if(SPI_SS4) begin
		cnt2 <= 0;
		bytecnt <= 0;
	end else begin
		// don't shift in last bit. It is evaluated directly
		// when writing to ram
		if(cnt2 != 7)
			sbuf2 <= { sbuf2[5:0], SPI_DO };

		cnt2 <= cnt2 + 1'd1;

		// received a byte
		if(cnt2 == 7) begin
			bytecnt <= bytecnt + 1'd1;
			// read 514 byte/sector (512 + 2 CRC)
			if (bytecnt == 513) bytecnt <= 0;
			// don't send the CRC bytes
			if (~bytecnt[9]) begin
				data_w2 <= {sbuf2, SPI_DO};
				rclk2 <= ~rclk2;
			end
		end
	end
end

end
endgenerate

always@(posedge clk_sys) begin
	// bring flags from spi clock domain into core clock domain
	reg rclkD, rclkD2;
	reg rclk2D, rclk2D2;
	reg addr_resetD, addr_resetD2;
	reg wr_int, wr_int_direct;
	reg [24:0] addr;

	{ rclkD, rclkD2 } <= { rclk, rclkD };
	{ rclk2D ,rclk2D2 } <= { rclk2, rclk2D };
	{ addr_resetD, addr_resetD2 } <= { addr_reset, addr_resetD };

	ioctl_wr <= 0;

	if (!downloading_reg) ioctl_download <= 0;

	if (~clkref_n) begin
		wr_int <= 0;
		wr_int_direct <= 0;
		if (wr_int || wr_int_direct) begin
			ioctl_dout <= wr_int ? data_w : data_w2;
			ioctl_wr <= 1;
			addr <= addr + 1'd1;
			ioctl_addr <= addr;
		end
	end

	// detect transfer start from the SPI receiver
	if(addr_resetD ^ addr_resetD2) begin
		addr <= START_ADDR;
		ioctl_index <= index_reg;
		ioctl_download <= 1;
	end

	// detect new byte from the SPI receiver
	if (rclkD ^ rclkD2)   wr_int <= 1;
	if (rclk2D ^ rclk2D2) wr_int_direct <= 1;
end

endmodule
