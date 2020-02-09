///////////////////////////////////////////// 
//  This module includes the SDRAM model
//  when used to simulate the core at the game level (instead of MiST(er) level)
//  this module also adds the SDRAM controller
// 
// 

`timescale 1ns/1ps

module test_harness(
    output  reg      rst = 1'b0,
    output  reg      clk27,
    input            pxl_cen,
    input            pxl_clk, 
    input            pxl_vb,
    input            pxl_hb,
    input   [21:0]   sdram_addr,
    output  [15:0]   data_read,
    output           loop_rst,
    input            autorefresh,
    input            H0,
    output           downloading,
    input            dwnld_busy,
    output    [22:0] ioctl_addr,
    output    [ 7:0] ioctl_data,
    output           ioctl_wr,
    // Video dumping
    input             HS,
    input             VS,
    input       [3:0] red,
    input       [3:0] green,
    input       [3:0] blue,
    output reg [31:0] frame_cnt,
    // SPI
    output       SPI_SCK,
    output       SPI_DI,  // SPI always from FPGA's view
    input        SPI_DO,
    output       SPI_SS2,
    output       SPI_SS3,
    output       CONF_DATA0,
    // SDRAM
    inout [15:0] SDRAM_DQ,
    inout [12:0] SDRAM_A,
    inout        SDRAM_DQML,
    inout        SDRAM_DQMH,
    inout        SDRAM_nWE,
    inout        SDRAM_nCAS,
    inout        SDRAM_nRAS,
    inout        SDRAM_nCS,
    inout [1:0]  SDRAM_BA,
    inout        SDRAM_CLK,
    inout        SDRAM_CKE
);

parameter sdram_instance = 1, GAME_ROMNAME="_PASS ROM NAME to test_harness_";
parameter TX_LEN = 207;

////////////////////////////////////////////////////////////////////
// video output dump
// this is a binary bile with 32 bits per pixel. First 8 bits are the alpha, and set to 0xFF
// The rest are RGB in 8-bit format
// There is no dump while blanking. The inputs pxl_hb and pxl_vb are high during blanking
// The linux tool "convert" can process the raw stream and separate it into individual frames
// automatically

`ifdef DUMP_VIDEO
integer fvideo;
initial begin
    fvideo = $fopen("video.raw","wb");
end

wire [31:0] video_dump = { 8'hff, {2{red}}, {2{green}}, {2{blue}} };

// Define VIDEO_START with the first frame number for which
// video will be dumped. If undefined, it will start from frame 0
`ifndef VIDEO_START
`define VIDEO_START 0
`endif

always @(posedge pxl_clk) if(pxl_cen && frame_cnt>=`VIDEO_START && !downloading) begin
    if( !pxl_hb && !pxl_vb ) $fwrite(fvideo,"%u", video_dump);
end

`endif

////////////////////////////////////////////////////////////////////
initial frame_cnt=0;
always @(posedge pxl_vb ) begin
    frame_cnt<=frame_cnt+1;
    $display("New frame %d", frame_cnt);
end

`ifdef MAXFRAME
reg frames_done=1'b0;
always @(negedge pxl_vb)
    if( frame_cnt == `MAXFRAME ) frames_done <= 1'b1;
`else
reg frames_done=1'b1;
`endif

wire spi_done;
integer fincnt;

// The PLL is only added if the top level does not already include it
`ifndef MISTER
`ifndef MIST
wire clk_rom;
pll_game_mist u_pll(
    .inclk0 ( 1'b0    ),
    .c0     ( clk     ),     // 12
    .c1     (         ),     // 96
    // unused
    //.c3     (         ),     // 96 (shifted by -2.5ns)
    .locked (         )
);

assign clk_rom = clk;

generate
    if (sdram_instance==1) begin
        assign #5 SDRAM_CLK = clk_rom;

        jtframe_sdram u_sdram(
            .rst            ( rst           ),
            .clk            ( clk_rom       ), // 96MHz = 32 * 6 MHz -> CL=2
            .cen12          ( cen12         ),
            .H0             ( H0            ),
            .loop_rst       ( loop_rst      ),
            .autorefresh    ( autorefresh   ),
            .data_read      ( data_read     ),
            // ROM-load interface
            .downloading    ( downloading   ),
            .prog_addr      ( ioctl_addr    ),
            .prog_data      ( ioctl_data    ),
            .prog_we        ( ioctl_wr      ),
            .sdram_addr     ( sdram_addr    ),
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
    end
endgenerate
`endif
`endif

////////////////////////////////////////////////////////////////////
always @(posedge clk27)
    if( spi_done && frames_done ) begin
        for( fincnt=0; fincnt<`SIM_MS; fincnt=fincnt+1 ) begin
            #(1000*1000); // ms
            $display("%d ms",fincnt+1);
        end
        $finish;
    end

initial begin
    clk27 = 1'b0;
    forever clk27 = #(37.037/2) ~clk27; // 27 MHz
end

reg rst_base=1'b1;

initial begin
    rst_base = 1'b1;
    #100 rst_base = 1'b0;
    #150 rst_base = 1'b1;
    #2500 rst_base=1'b0;
end

integer rst_cnt;

always @(negedge clk27 or posedge rst_base)
    if( rst_base ) begin
        rst <= 1'b1;
        rst_cnt <= 2;
    end else begin
        if(rst_cnt) rst_cnt<=rst_cnt-1;
        else rst<=rst_base;
    end

`ifdef FASTSDRAM
quick_sdram mist_sdram(
    .SDRAM_DQ   ( SDRAM_DQ      ),
    .SDRAM_A    ( SDRAM_A       ),
    .SDRAM_CLK  ( SDRAM_CLK     ),
    .SDRAM_nCS  ( SDRAM_nCS     ),
    .SDRAM_nRAS ( SDRAM_nRAS    ),
    .SDRAM_nCAS ( SDRAM_nCAS    ),
    .SDRAM_nWE  ( SDRAM_nWE     )
);
`else
mt48lc16m16a2 #(.filename(GAME_ROMNAME)) mist_sdram (
    .Dq         ( SDRAM_DQ      ),
    .Addr       ( SDRAM_A       ),
    .Ba         ( SDRAM_BA      ),
    .Clk        ( SDRAM_CLK     ),
    .Cke        ( SDRAM_CKE     ),
    .Cs_n       ( SDRAM_nCS     ),
    .Ras_n      ( SDRAM_nRAS    ),
    .Cas_n      ( SDRAM_nCAS    ),
    .We_n       ( SDRAM_nWE     ),
    .Dqm        ( {SDRAM_DQMH,SDRAM_DQML}   ),
    .downloading( dwnld_busy    ),
    .VS         ( VS            ),
    .frame_cnt  ( frame_cnt     )
);
`endif

//`ifdef LOADROM
spitx #(.filename(GAME_ROMNAME), .TX_LEN(TX_LEN) )
    u_spitx(
    .rst        ( rst        ),
    .SPI_DO     ( 1'b0       ),
    .SPI_SCK    ( SPI_SCK    ),
    .SPI_DI     ( SPI_DI     ),
    .SPI_SS2    ( SPI_SS2    ),
    .SPI_SS3    ( SPI_SS3    ),
    .SPI_SS4    (            ),
    .CONF_DATA0 ( CONF_DATA0 ),
    .spi_done   ( spi_done   )
);

data_io datain (
    .sck        (SPI_SCK      ),
    .ss         (SPI_SS2      ),
    .sdi        (SPI_DI       ),
    .downloading_sdram(downloading  ),
    .index      (             ),
    .clk_sdram  (SDRAM_CLK    ),
    .ioctl_addr ( ioctl_addr  ),
    .ioctl_data ( ioctl_data  ),
    .ioctl_wr   ( ioctl_wr    )
);
// `else
// assign downloading = 0;
// assign romload_addr = 0;
// assign romload_data = 0;
// assign spi_done = 1'b1;
// assign SPI_SS2  = 1'b0;
// `endif

endmodule // jt_1942_a_test