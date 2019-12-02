//
// FX68K
//
// M68000 cycle accurate, fully synchronous
// Copyright (c) 2018 by Jorge Cwik
// 
// TODO:
// - Everything except bus retry already implemented.

`timescale 1 ns / 1 ns

// Define this to run a self contained compilation test build
// `define FX68K_TEST

localparam CF = 0, VF = 1, ZF = 2, NF = 3, XF = 4, SF = 13;

localparam UADDR_WIDTH = 10;
localparam UROM_WIDTH = 17;
localparam UROM_DEPTH = 1024;

localparam NADDR_WIDTH = 9;
localparam NANO_WIDTH = 68;
localparam NANO_DEPTH = 336;

localparam BSER1_NMA = 'h003;
localparam RSTP0_NMA = 'h002;
localparam HALT1_NMA = 'h001;
localparam TRAC1_NMA = 'h1C0;
localparam ITLX1_NMA = 'h1C4;

localparam TVN_SPURIOUS = 12;
localparam TVN_AUTOVEC = 13;
localparam TVN_INTERRUPT = 15;

localparam NANO_DOB_DBD = 2'b01;
localparam NANO_DOB_ADB = 2'b10;
localparam NANO_DOB_ALU = 2'b11;



module fx68k(
    input clk,
    
    // These two signals don't need to be registered. They are not async reset.
    input extReset,         // External sync reset on emulated system
    input pwrUp,            // Asserted together with reset on emulated system coldstart    
    input enPhi1, enPhi2,   // Clock enables. Next cycle is PHI1 or PHI2

    output eRWn, output ASn, output LDSn, output UDSn,
    output reg E, output VMAn,    
    output FC0, output FC1, output FC2,
    output BGn,
    output oRESETn, output oHALTEDn,
    input DTACKn, input VPAn,
    input BERRn,
    input BRn, BGACKn,
    input IPL0n, input IPL1n, input IPL2n,
    input [15:0] iEdb, output [15:0] oEdb,
    output [23:1] eab
    );
    
    // wire clock = Clks_clk;
    wire Clks_clk;
    wire Clks_extReset;         // External sync reset on emulated system
    wire Clks_pwrUp;            // Asserted together with reset on emulated system coldstart
    wire Clks_enPhi1;
    wire Clks_enPhi2;   // Clock enables. Next cycle is PHI1 or PHI2
    
    assign Clks_clk = clk;  
    assign Clks_extReset = extReset;
    assign Clks_pwrUp = pwrUp;  
    assign Clks_enPhi1 = enPhi1;
    assign Clks_enPhi2 = enPhi2;
    
    wire wClk;
    
    // Internal sub clocks T1-T4
    //enum int unsigned { T0 = 0, T1, T2, T3, T4} tState;
	 reg tState;
    wire enT1 = Clks_enPhi1 & (tState == 4) & ~wClk;
    wire enT2 = Clks_enPhi2 & (tState == 1);
    wire enT3 = Clks_enPhi1 & (tState == 2);
    wire enT4 = Clks_enPhi2 & ((tState == 0) | (tState == 3));
    
    // T4 continues ticking during reset and group0 exception.
    // We also need it to erase ucode output latched on T4.
    always @( posedge Clks_clk) begin
        if( Clks_pwrUp)
            tState <= 0;
        else begin
        case( tState)
        0: if( Clks_enPhi2) tState <= 4;
        1: if( Clks_enPhi2) tState <= 2;
        2: if( Clks_enPhi1) tState <= 3;
        3: if( Clks_enPhi2) tState <= 4;
        4: if( Clks_enPhi1) tState <= wClk ? 0 : 1;
        endcase
        end
    end
    
    // The following signals are synchronized with 3 couplers, phi1-phi2-phi1.
    // Will be valid internally one cycle later if changed at the rasing edge of the clock.
    //
    // DTACK, BERR
        
    // DTACK valid at S6 if changed at the rasing edge of S4 to avoid wait states.
    // SNC (sncClkEn) is deasserted together (unless DTACK asserted too early).
    //  
    // We synchronize some signals half clock earlier. We compensate later
    reg rDtack, rBerr;
    reg [2:0] rIpl, iIpl;
    reg Vpai, BeI, BRi, BgackI, BeiDelay;
    // reg rBR;
    wire BeDebounced = ~( BeI | BeiDelay);

    always @( posedge Clks_clk) begin
        if( Clks_pwrUp) begin
            rBerr <= 1'b0;
            BeI <= 1'b0;
        end
        else if( Clks_enPhi2) begin
            rDtack <= DTACKn;
            rBerr <= BERRn;
            rIpl <= ~{ IPL2n, IPL1n, IPL0n};
            iIpl <= rIpl;
            
            // rBR <= BRn;          // Needed for cycle accuracy but only if BR is changed on the wrong edge of the clock
        end
        else if( Clks_enPhi1) begin
            Vpai <= VPAn;
            BeI <= rBerr;
            BeiDelay <= BeI;
            
            BRi <= BRn;
            BgackI <= BGACKn;
            // BRi <= rBR;
        end 
    end

    // Instantiate micro and nano rom
    reg [NANO_WIDTH-1:0] nanoLatch;
    wire [NANO_WIDTH-1:0] nanoOutput;
    reg [UROM_WIDTH-1:0] microLatch;
    wire [UROM_WIDTH-1:0] microOutput;
    
    reg [UADDR_WIDTH-1:0] microAddr;
	 wire [UADDR_WIDTH-1:0] nma; 
    reg [NADDR_WIDTH-1:0] nanoAddr; 
	 wire [NADDR_WIDTH-1:0] orgAddr;
    wire rstUrom;

    // For the time being, address translation is done for nanorom only. 
    microToNanoAddr microToNanoAddr( .uAddr( nma), .orgAddr);
    
    // Output of these modules will be updated at T2 at the latest (depending on clock division)
    
    nanoRom nanoRom( .clk( Clks_clk), .nanoAddr, .nanoOutput);
    uRom uRom( .clk( Clks_clk), .microAddr, .microOutput);
    
    always @( posedge Clks_clk) begin
        // uaddr originally latched on T1, except bits 6 & 7, the conditional bits, on T2
        // Seems we can latch whole address at either T1 or T2

        // Originally it's invalid on hardware reset, and forced later when coming out of reset
        if( Clks_pwrUp) begin
            microAddr <= RSTP0_NMA;
            nanoAddr <= RSTP0_NMA;
        end
        else if( enT1) begin
            microAddr <= nma;
            nanoAddr <= orgAddr;                // Register translated uaddr to naddr
        end
            
        if( Clks_extReset) begin
            microLatch <= 1'b0;
            nanoLatch <= 1'b0;
        end
        else if( rstUrom) begin
            // Originally reset these bits only. Not strictly needed like this.
            // Can reset the whole register if it is important.
            { microLatch[16], microLatch[15], microLatch[0]} <= 1'b0;
            nanoLatch <= 1'b0;
        end
        else if( enT3) begin
            microLatch <= microOutput;
            nanoLatch <= nanoOutput;
        end
                    
    end
    

    // Decoded nanocode signals
    wire Nanod_permStart;
    wire Nanod_waitBusFinish;
    wire Nanod_isWrite;
    wire Nanod_busByte;
    wire Nanod_isRmc;
    wire Nanod_noLowByte, Nanod_noHighByte;
    wire Nanod_updTpend, Nanod_clrTpend;
    wire Nanod_tvn2Ftu, Nanod_const2Ftu;
    wire Nanod_ftu2Dbl, Nanod_ftu2Abl;
    wire Nanod_abl2Pren, Nanod_updPren;
    wire Nanod_inl2psw, Nanod_ftu2Sr, Nanod_sr2Ftu, Nanod_ftu2Ccr, Nanod_pswIToFtu;
    wire Nanod_ird2Ftu, Nanod_ssw2Ftu;
    wire Nanod_initST;
    wire Nanod_Ir2Ird;
    wire Nanod_auClkEn, Nanod_noSpAlign;
    wire [2:0] Nanod_auCntrl;
    wire Nanod_todbin, Nanod_toIrc;
    wire Nanod_dbl2Atl, Nanod_abl2Atl, Nanod_atl2Abl, Nanod_atl2Dbl;
    wire Nanod_abh2Ath, Nanod_dbh2Ath;
    wire Nanod_ath2Dbh, Nanod_ath2Abh;
    wire Nanod_db2Aob, Nanod_ab2Aob, Nanod_au2Aob;
    wire Nanod_aob2Ab, Nanod_updSsw;
    wire [1:0] Nanod_dobCtrl;
    wire Nanod_abh2reg, Nanod_abl2reg;
    wire Nanod_reg2abl, Nanod_reg2abh;
    wire Nanod_dbh2reg, Nanod_dbl2reg;
    wire Nanod_reg2dbl, Nanod_reg2dbh;
    wire Nanod_ssp, Nanod_pchdbh, Nanod_pcldbl, Nanod_pclabl, Nanod_pchabh;
    wire Nanod_rxh2dbh, Nanod_rxh2abh;
    wire Nanod_dbl2rxl, Nanod_dbh2rxh;
    wire Nanod_rxl2db, Nanod_rxl2ab;
    wire Nanod_abl2rxl, Nanod_abh2rxh;
    wire Nanod_dbh2ryh, Nanod_abh2ryh;
    wire Nanod_ryl2db, Nanod_ryl2ab;
    wire Nanod_ryh2dbh, Nanod_ryh2abh;
    wire Nanod_dbl2ryl, Nanod_abl2ryl;
    wire Nanod_rz;
    wire Nanod_rxlDbl;
    wire [2:0] Nanod_aluColumn;
    wire [1:0] Nanod_aluDctrl;
    wire Nanod_aluActrl;
    wire Nanod_aluInit, Nanod_aluFinish;
    wire Nanod_abd2Dcr, Nanod_dcr2Dbd;
    wire Nanod_dbd2Alue, Nanod_alue2Dbd;
    wire Nanod_dbd2Alub, Nanod_abd2Alub;
    wire Nanod_alu2Dbd, Nanod_alu2Abd;
    wire Nanod_au2Db, Nanod_au2Ab, Nanod_au2Pc;
    wire Nanod_dbin2Abd, Nanod_dbin2Dbd;
    wire Nanod_extDbh, Nanod_extAbh;
    wire Nanod_ablAbd, Nanod_ablAbh;
    wire Nanod_dblDbd, Nanod_dblDbh;
    wire Nanod_abdIsByte;

    // IRD decoded control signals
    wire        Irdecod_isPcRel;
    wire        Irdecod_isTas;
    wire        Irdecod_implicitSp;
    wire        Irdecod_toCcr;
    wire        Irdecod_rxIsDt, Irdecod_ryIsDt;
    wire        Irdecod_rxIsUsp, Irdecod_rxIsMovem, Irdecod_movemPreDecr;
    wire        Irdecod_isByte;
    wire        Irdecod_isMovep;
    wire [ 2:0] Irdecod_rx, Irdecod_ry;
    wire        Irdecod_rxIsAreg, Irdecod_ryIsAreg;
    wire [15:0] Irdecod_ftuConst;
    wire [ 5:0] Irdecod_macroTvn;
    wire        Irdecod_inhibitCcr;


    //  
    reg Tpend;
    reg intPend;                                            // Interrupt pending
    reg pswT, pswS;
    reg [ 2:0] pswI;
    wire [7:0] ccr;
    
    wire [15:0] psw = { pswT, 1'b0, pswS, 2'b00, pswI, ccr};

    reg [15:0] ftu;
    wire [15:0] Irc;	
    reg [15:0] Ir, Ird;
    
    wire [15:0] alue;
    wire [15:0] Abl;
    wire prenEmpty, au05z, dcr4, ze;
    
    wire [UADDR_WIDTH-1:0] a1, a2, a3;
    wire isPriv, isIllegal, isLineA, isLineF;
    

    // IR & IRD forwarding
    always @( posedge Clks_clk) begin
        if( enT1) begin
            if( Nanod_Ir2Ird)
                Ird <= Ir;
            else if(microLatch[0])      // prevented by IR => IRD !
                Ir <= Irc;
        end
    end
    
    wire [3:0] tvn;
    wire waitBusCycle, busStarting;
    wire BusRetry = 1'b0;
    wire busAddrErr;
    wire bciWrite;                      // Last bus cycle was write
    wire bgBlock, busAvail;
    wire addrOe;

    wire busIsByte = Nanod_busByte & (Irdecod_isByte | Irdecod_isMovep);
    wire aob0;
    
    reg iStop;                              // Internal signal for ending bus cycle
    reg A0Err;                              // Force bus/address error ucode
    reg excRst;                             // Signal reset exception to sequencer
    reg BerrA;
    reg Spuria, Avia;
    wire Iac;
    
    reg rAddrErr, iBusErr, Err6591;
    wire iAddrErr = rAddrErr & addrOe;      // To simulate async reset
    wire enErrClk;

    // Reset micro/nano latch after T4 of the current ublock.
    assign rstUrom = Clks_enPhi1 & enErrClk;

    uaddrDecode uaddrDecode( .opcode( Ir), .a1, .a2, .a3, .isPriv, .isIllegal, .isLineA, .isLineF, .lineBmap());

    sequencer sequencer( 
        .Clks_clk,
        .Clks_extReset,         // External sync reset on emulated system
        .Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
        .Clks_enPhi1,
        .Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
        .enT3, .microLatch, .Ird,
        .A0Err, .excRst, .BerrA, .busAddrErr, .Spuria, .Avia,
        .Tpend, .intPend, .isIllegal, .isPriv, .isLineA, .isLineF,
        .nma, .a1, .a2, .a3, .tvn,
        .psw, .prenEmpty, .au05z, .dcr4, .ze, .alue01( alue[1:0]), .i11( Irc[ 11]) );

    excUnit excUnit( 
        .Clks_clk,
        .Clks_extReset,         // External sync reset on emulated system
        .Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
        .Clks_enPhi1,
        .Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
        .Nanod_permStart,
        .Nanod_waitBusFinish,
        .Nanod_isWrite,
        .Nanod_busByte,
        .Nanod_isRmc,
        .Nanod_noLowByte, .Nanod_noHighByte,
        .Nanod_updTpend, .Nanod_clrTpend,
        .Nanod_tvn2Ftu, .Nanod_const2Ftu,
        .Nanod_ftu2Dbl, .Nanod_ftu2Abl,
        .Nanod_abl2Pren, .Nanod_updPren,
        .Nanod_inl2psw, .Nanod_ftu2Sr, .Nanod_sr2Ftu, .Nanod_ftu2Ccr, .Nanod_pswIToFtu,
        .Nanod_ird2Ftu, .Nanod_ssw2Ftu,
        .Nanod_initST,
        .Nanod_Ir2Ird,
        .Nanod_auClkEn, .Nanod_noSpAlign,
        .Nanod_auCntrl,
        .Nanod_todbin, .Nanod_toIrc,
        .Nanod_dbl2Atl, .Nanod_abl2Atl, .Nanod_atl2Abl, .Nanod_atl2Dbl,
        .Nanod_abh2Ath, .Nanod_dbh2Ath,
        .Nanod_ath2Dbh, .Nanod_ath2Abh,
        .Nanod_db2Aob, .Nanod_ab2Aob, .Nanod_au2Aob,
        .Nanod_aob2Ab, .Nanod_updSsw,
        .Nanod_dobCtrl,
        .Nanod_abh2reg, .Nanod_abl2reg,
        .Nanod_reg2abl, .Nanod_reg2abh,
        .Nanod_dbh2reg, .Nanod_dbl2reg,
        .Nanod_reg2dbl, .Nanod_reg2dbh,
        .Nanod_ssp, .Nanod_pchdbh, .Nanod_pcldbl, .Nanod_pclabl, .Nanod_pchabh,
        .Nanod_rxh2dbh, .Nanod_rxh2abh,
        .Nanod_dbl2rxl, .Nanod_dbh2rxh,
        .Nanod_rxl2db, .Nanod_rxl2ab,
        .Nanod_abl2rxl, .Nanod_abh2rxh,
        .Nanod_dbh2ryh, .Nanod_abh2ryh,
        .Nanod_ryl2db, .Nanod_ryl2ab,
        .Nanod_ryh2dbh, .Nanod_ryh2abh,
        .Nanod_dbl2ryl, .Nanod_abl2ryl,
        .Nanod_rz,
        .Nanod_rxlDbl,
        .Nanod_aluColumn,
        .Nanod_aluDctrl,
        .Nanod_aluActrl,
        .Nanod_aluInit, .Nanod_aluFinish,
        .Nanod_abd2Dcr, .Nanod_dcr2Dbd,
        .Nanod_dbd2Alue, .Nanod_alue2Dbd,
        .Nanod_dbd2Alub, .Nanod_abd2Alub,
        .Nanod_alu2Dbd, .Nanod_alu2Abd,
        .Nanod_au2Db, .Nanod_au2Ab, .Nanod_au2Pc,
        .Nanod_dbin2Abd, .Nanod_dbin2Dbd,
        .Nanod_extDbh, .Nanod_extAbh,
        .Nanod_ablAbd, .Nanod_ablAbh,
        .Nanod_dblDbd, .Nanod_dblDbh,
        .Nanod_abdIsByte,
        
        
        .Irdecod_isPcRel,
        .Irdecod_isTas,
        .Irdecod_implicitSp,
        .Irdecod_toCcr,
        .Irdecod_rxIsDt,
        .Irdecod_ryIsDt,
        .Irdecod_rxIsUsp,
        .Irdecod_rxIsMovem,
        .Irdecod_movemPreDecr,
        .Irdecod_isByte,
        .Irdecod_isMovep,
        .Irdecod_rx,
        .Irdecod_ry,
        .Irdecod_rxIsAreg,
        .Irdecod_ryIsAreg,
        .Irdecod_ftuConst,
        .Irdecod_macroTvn,
        .Irdecod_inhibitCcr,    
        .enT1, .enT2, .enT3, .enT4,
        .Ird, .ftu, .iEdb, .pswS,
        .prenEmpty, .au05z, .dcr4, .ze, .AblOut( Abl), .eab, .aob0, .Irc, .oEdb,
        .alue, .ccr);

    nDecoder3 nDecoder( 
        .Clks_clk,
        .Clks_extReset,         // External sync reset on emulated system
        .Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
        .Clks_enPhi1,
        .Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
        .Nanod_permStart,
        .Nanod_waitBusFinish,
        .Nanod_isWrite,
        .Nanod_busByte,
        .Nanod_isRmc,
        .Nanod_noLowByte, .Nanod_noHighByte,
        .Nanod_updTpend, .Nanod_clrTpend,
        .Nanod_tvn2Ftu, .Nanod_const2Ftu,
        .Nanod_ftu2Dbl, .Nanod_ftu2Abl,
        .Nanod_abl2Pren, .Nanod_updPren,
        .Nanod_inl2psw, .Nanod_ftu2Sr, .Nanod_sr2Ftu, .Nanod_ftu2Ccr, .Nanod_pswIToFtu,
        .Nanod_ird2Ftu, .Nanod_ssw2Ftu,
        .Nanod_initST,
        .Nanod_Ir2Ird,
        .Nanod_auClkEn, .Nanod_noSpAlign,
        .Nanod_auCntrl,
        .Nanod_todbin, .Nanod_toIrc,
        .Nanod_dbl2Atl, .Nanod_abl2Atl, .Nanod_atl2Abl, .Nanod_atl2Dbl,
        .Nanod_abh2Ath, .Nanod_dbh2Ath,
        .Nanod_ath2Dbh, .Nanod_ath2Abh,
        .Nanod_db2Aob, .Nanod_ab2Aob, .Nanod_au2Aob,
        .Nanod_aob2Ab, .Nanod_updSsw,
        .Nanod_dobCtrl,
        .Nanod_abh2reg, .Nanod_abl2reg,
        .Nanod_reg2abl, .Nanod_reg2abh,
        .Nanod_dbh2reg, .Nanod_dbl2reg,
        .Nanod_reg2dbl, .Nanod_reg2dbh,
        .Nanod_ssp, .Nanod_pchdbh, .Nanod_pcldbl, .Nanod_pclabl, .Nanod_pchabh,
        .Nanod_rxh2dbh, .Nanod_rxh2abh,
        .Nanod_dbl2rxl, .Nanod_dbh2rxh,
        .Nanod_rxl2db, .Nanod_rxl2ab,
        .Nanod_abl2rxl, .Nanod_abh2rxh,
        .Nanod_dbh2ryh, .Nanod_abh2ryh,
        .Nanod_ryl2db, .Nanod_ryl2ab,
        .Nanod_ryh2dbh, .Nanod_ryh2abh,
        .Nanod_dbl2ryl, .Nanod_abl2ryl,
        .Nanod_rz,
        .Nanod_rxlDbl,
        .Nanod_aluColumn,
        .Nanod_aluDctrl,
        .Nanod_aluActrl,
        .Nanod_aluInit, .Nanod_aluFinish,
        .Nanod_abd2Dcr, .Nanod_dcr2Dbd,
        .Nanod_dbd2Alue, .Nanod_alue2Dbd,
        .Nanod_dbd2Alub, .Nanod_abd2Alub,
        .Nanod_alu2Dbd, .Nanod_alu2Abd,
        .Nanod_au2Db, .Nanod_au2Ab, .Nanod_au2Pc,
        .Nanod_dbin2Abd, .Nanod_dbin2Dbd,
        .Nanod_extDbh, .Nanod_extAbh,
        .Nanod_ablAbd, .Nanod_ablAbh,
        .Nanod_dblDbd, .Nanod_dblDbh,
        .Nanod_abdIsByte,
        
        
        .Irdecod_isPcRel,
        .Irdecod_isTas,
        .Irdecod_implicitSp,
        .Irdecod_toCcr,
        .Irdecod_rxIsDt,
        .Irdecod_ryIsDt,
        .Irdecod_rxIsUsp,
        .Irdecod_rxIsMovem,
        .Irdecod_movemPreDecr,
        .Irdecod_isByte,
        .Irdecod_isMovep,
        .Irdecod_rx,
        .Irdecod_ry,
        .Irdecod_rxIsAreg,
        .Irdecod_ryIsAreg,
        .Irdecod_ftuConst,
        .Irdecod_macroTvn,
        .Irdecod_inhibitCcr,    
        .enT2, .enT4, .microLatch, .nanoLatch);
    
    irdDecode irdDecode( 
            .ird( Ird),
            .Irdecod_isPcRel,
            .Irdecod_isTas,
            .Irdecod_implicitSp,
            .Irdecod_toCcr,
            .Irdecod_rxIsDt,
            .Irdecod_ryIsDt,
            .Irdecod_rxIsUsp,
            .Irdecod_rxIsMovem,
            .Irdecod_movemPreDecr,
            .Irdecod_isByte,
            .Irdecod_isMovep,
            .Irdecod_rx,
            .Irdecod_ry,
            .Irdecod_rxIsAreg,
            .Irdecod_ryIsAreg,
            .Irdecod_ftuConst,
            .Irdecod_macroTvn,
            .Irdecod_inhibitCcr
        );
    
    busControl busControl( 
        .Clks_clk,
        .Clks_extReset,         // External sync reset on emulated system
        .Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
        .Clks_enPhi1,
        .Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
        .enT1, .enT4, .permStart( Nanod_permStart), .permStop( Nanod_waitBusFinish), .iStop,
        .aob0, .isWrite( Nanod_isWrite), .isRmc( Nanod_isRmc), .isByte( busIsByte), .busAvail,
        .bciWrite, .addrOe, .bgBlock, .waitBusCycle, .busStarting, .busAddrErr,
        .rDtack, .BeDebounced, .Vpai,
        .ASn, .LDSn, .UDSn, .eRWn);
        
    busArbiter busArbiter( 
        .Clks_clk,
        .Clks_extReset,         // External sync reset on emulated system
        .Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
        .Clks_enPhi1,
        .Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
        .BRi, .BgackI, .Halti( 1'b1), .bgBlock, .busAvail, .BGn);
        
        
    // Output reset & halt control
    wire [1:0] uFc = microLatch[ 16:15];
    reg oReset, oHalted;
    assign oRESETn = !oReset;
    assign oHALTEDn = !oHalted;
    
    // FC without permStart is special, either reset or halt
    always @( posedge Clks_clk) begin
        if( Clks_pwrUp) begin
            oReset <= 1'b0;
            oHalted <= 1'b0;
        end
        else if( enT1) begin
            oReset <= (uFc == 2'b01) & !Nanod_permStart;
            oHalted <= (uFc == 2'b10) & !Nanod_permStart;
        end
    end
        
    reg [2:0] rFC;
    assign { FC2, FC1, FC0} = rFC;                  // ~rFC;
    assign Iac = {rFC == 3'b111};                   // & Control output enable !!

    always @( posedge Clks_clk) begin
        if( Clks_extReset)
            rFC <= 1'b0;
        else if( enT1 & Nanod_permStart) begin      // S0 phase of bus cycle
            rFC[2] <= pswS;
            // PC relativ access is marked as FC type 'n' (0) at ucode.
            // We don't care about RZ in this case. Those uinstructions with RZ don't start a bus cycle.
            rFC[1] <= microLatch[ 16] | ( ~microLatch[ 15] & ~Irdecod_isPcRel);
            rFC[0] <= microLatch[ 15] | ( ~microLatch[ 16] & Irdecod_isPcRel);
        end
    end
    
        
    // IPL interface
    reg [2:0] inl;                          // Int level latch
    reg updIll;
    reg prevNmi;
    
    wire nmi = (iIpl == 3'b111);
    wire iplStable = (iIpl == rIpl);
    wire iplComp = iIpl > pswI;

    always @( posedge Clks_clk) begin
        if( Clks_extReset) begin
            intPend <= 1'b0;
            prevNmi <= 1'b0;
        end
        else begin
            if( Clks_enPhi2)
                prevNmi <= nmi;
                
            // Originally async RS-Latch on PHI2, followed by a transparent latch on T2
            // Tricky because they might change simultaneously
            // Syncronous on PHI2 is equivalent as long as the output is read on T3!
            
            // Set on stable & NMI edge or compare
            // Clear on: NMI Iack or (stable & !NMI & !Compare)

            if( Clks_enPhi2) begin
                if( iplStable & ((nmi & ~prevNmi) | iplComp) )
                    intPend <= 1'b1;
                else if( ((inl == 3'b111) & Iac) | (iplStable & !nmi & !iplComp) )
                    intPend <= 1'b0;
            end         
        end
        
        if( Clks_extReset) begin
            inl <= 1'b1;
            updIll <= 1'b0;
        end
        else if( enT4)
            updIll <= microLatch[0];        // Update on any IRC->IR
        else if( enT1 & updIll)
            inl <= iIpl;                    // Timing is correct.
            
        // Spurious interrupt, BERR on Interrupt Ack.
        // Autovector interrupt. VPA on IACK.
        // Timing is tight. Spuria is deasserted just after exception exception is recorded.
        if( enT4) begin
            Spuria <= ~BeiDelay & Iac;
            Avia <= ~Vpai & Iac;
        end
            
    end
        
    assign enErrClk = iAddrErr | iBusErr;
    assign wClk = waitBusCycle | ~BeI | iAddrErr | Err6591;
    
    // E clock and counter, VMA
    reg [3:0] eCntr;
    reg rVma;
    
    assign VMAn = rVma;
    
    // Internal stop just one cycle before E falling edge
    wire xVma = ~rVma & (eCntr == 8);
    
    always @( posedge Clks_clk) begin
        if( Clks_pwrUp) begin
            E <= 1'b0;
            eCntr <=1'b0;
            rVma <= 1'b1;
        end
        if( Clks_enPhi2) begin
            if( eCntr == 9)
                E <= 1'b0;
            else if( eCntr == 5)
                E <= 1'b1;

            if( eCntr == 9)
                eCntr <= 1'b0;
            else
                eCntr <= eCntr + 1'b1;
        end
        
        if( Clks_enPhi2 & addrOe & ~Vpai & (eCntr == 3))
            rVma <= 1'b0;
        else if( Clks_enPhi1 & eCntr == 1'b0)
            rVma <= 1'b1;
    end
        
    always @( posedge Clks_clk) begin
    
        // This timing is critical to stop the clock phases at the exact point on bus/addr error.
        // Timing should be such that current ublock completes (up to T3 or T4).
        // But T1 for the next ublock shouldn't happen. Next T1 only after resetting ucode and ncode latches.
        
        if( Clks_extReset)
            rAddrErr <= 1'b0;
        else if( Clks_enPhi1) begin
            if( busAddrErr & addrOe)        // Not on T1 ?!
                rAddrErr <= 1'b1;
            else if( ~addrOe)               // Actually async reset!
                rAddrErr <= 1'b0;
        end
        
        if( Clks_extReset)
            iBusErr <= 1'b0;
        else if( Clks_enPhi1) begin
            iBusErr <= ( BerrA & ~BeI & ~Iac & !BusRetry);
        end

        if( Clks_extReset)
            BerrA <= 1'b0;
        else if( Clks_enPhi2) begin
            if( ~BeI & ~Iac & addrOe)
                BerrA <= 1'b1;
            // else if( BeI & addrOe)           // Bad, async reset since addrOe raising edge
            else if( BeI & busStarting)         // So replaced with this that raises one cycle earlier
                BerrA <= 1'b0;
        end

        // Signal reset exception to sequencer.
        // Originally cleared on 1st T2 after permstart. Must keep it until TVN latched.
        if( Clks_extReset)
            excRst <= 1'b1;
        else if( enT2 & Nanod_permStart)
            excRst <= 1'b0;
        
        if( Clks_extReset)
            A0Err <= 1'b1;                              // A0 Reset
        else if( enT3)                                  // Keep set until new urom words are being latched
            A0Err <= 1'b0;
        else if( Clks_enPhi1 & enErrClk & (busAddrErr | BerrA))     // Check bus error timing
            A0Err <= 1'b1;
        
        if( Clks_extReset) begin
            iStop <= 1'b0;
            Err6591 <= 1'b0;
        end
        else if( Clks_enPhi1)
            Err6591 <= enErrClk;
        else if( Clks_enPhi2)
            iStop <= xVma | (Vpai & (iAddrErr | ~rBerr));
    end
    
    // PSW
    reg irdToCcr_t4;
    always @( posedge Clks_clk) begin                
        if( Clks_pwrUp) begin
            Tpend <= 1'b0;
            {pswT, pswS, pswI } <= 1'b0;
            irdToCcr_t4 <= 1'b0;
        end
        
        else if( enT4) begin
            irdToCcr_t4 <= Irdecod_toCcr;
        end
        
        else if( enT3) begin
        
            // UNIQUE IF !! 
            if( Nanod_updTpend)
                Tpend <= pswT;
            else if( Nanod_clrTpend)
                Tpend <= 1'b0;
            
            // UNIQUE IF !! 
            if( Nanod_ftu2Sr & !irdToCcr_t4)
                {pswT, pswS, pswI } <= { ftu[ 15], ftu[13], ftu[10:8]};
            else begin
                if( Nanod_initST) begin
                    pswS <= 1'b1;
                    pswT <= 1'b0;
                end
                if( Nanod_inl2psw)
                    pswI <= inl;
            end
                
        end
    end
        
    // FTU
    reg [4:0] ssw;
    reg [3:0] tvnLatch;
    reg [15:0] tvnMux;
    reg inExcept01;
    
    // Seems CPU has a buglet here.
    // Flagging group 0 exceptions from TVN might not work because some bus cycles happen before TVN is updated.
    // But doesn't matter because a group 0 exception inside another one will halt the CPU anyway and won't save the SSW.
        
    always @( posedge Clks_clk) begin
    
        // Updated at the start of the exception ucode
        if( Nanod_updSsw & enT3) begin
            ssw <= { ~bciWrite, inExcept01, rFC};
        end
    
        // Update TVN on T1 & IR=>IRD
        if( enT1 & Nanod_Ir2Ird) begin
            tvnLatch <= tvn;
            inExcept01 <= (tvn != 1);
        end
            
        if( Clks_pwrUp)
            ftu <= 1'b0;
        else if( enT3) begin
            case( 1'b1)
            Nanod_tvn2Ftu:              ftu <= tvnMux;
            
            // 0 on unused bits seem to come from ftuConst PLA previously clearing FBUS
            Nanod_sr2Ftu:               ftu <= {pswT, 1'b0, pswS, 2'b00, pswI, 3'b000, ccr[4:0] };
            
            Nanod_ird2Ftu:              ftu <= Ird;
            Nanod_ssw2Ftu:              ftu[4:0] <= ssw;                        // Undoc. Other bits must be preserved from IRD saved above!
            Nanod_pswIToFtu:            ftu <= { 12'hFFF, pswI, 1'b0};          // Interrupt level shifted
            Nanod_const2Ftu:            ftu <= Irdecod_ftuConst;
            Nanod_abl2Pren:             ftu <= Abl;                             // From ALU or datareg. Used for SR modify
            default:                    ftu <= ftu;
            endcase
        end
    end
    
    always @* begin
        if( inExcept01) begin
            // Unique IF !!!
            if( tvnLatch == TVN_SPURIOUS)
                tvnMux = {9'b0, 5'd24, 2'b00};
            else if( tvnLatch == TVN_AUTOVEC)
                tvnMux = {9'b0, 2'b11, pswI, 2'b00};                // Set TVN PLA decoder
            else if( tvnLatch == TVN_INTERRUPT)
                tvnMux = {6'b0, Ird[7:0], 2'b00};                   // Interrupt vector was read and transferred to IRD
            else
                tvnMux = {10'b0, tvnLatch, 2'b00};
        end
        else
            tvnMux = { 8'h0, Irdecod_macroTvn, 2'b00};
    end
                
endmodule

// Nanorom (plus) decoder for die nanocode
module nDecoder3( 
    input Clks_clk,
    input Clks_extReset,         // External sync reset on emulated system
    input Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
    input Clks_enPhi1,
    input Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2

    input        Irdecod_isPcRel,
    input        Irdecod_isTas,
    input        Irdecod_implicitSp,
    input        Irdecod_toCcr,
    input        Irdecod_rxIsDt,
    input        Irdecod_ryIsDt,
    input        Irdecod_rxIsUsp,
    input        Irdecod_rxIsMovem,
    input        Irdecod_movemPreDecr,
    input        Irdecod_isByte,
    input        Irdecod_isMovep,
    input [2:0]  Irdecod_rx,
    input [2:0]  Irdecod_ry,
    input        Irdecod_rxIsAreg,
    input        Irdecod_ryIsAreg,
    input [15:0] Irdecod_ftuConst,
    input [ 5:0] Irdecod_macroTvn,
    input        Irdecod_inhibitCcr,    

    output Nanod_permStart,
    output Nanod_waitBusFinish,
    output Nanod_isWrite,
    output Nanod_busByte,
    output reg Nanod_isRmc,
    output Nanod_noLowByte, Nanod_noHighByte,
    output Nanod_updTpend, Nanod_clrTpend,
    output Nanod_tvn2Ftu, Nanod_const2Ftu,
    output Nanod_ftu2Dbl, Nanod_ftu2Abl,
    output Nanod_abl2Pren, Nanod_updPren,
    output Nanod_inl2psw, Nanod_ftu2Sr, Nanod_sr2Ftu, Nanod_ftu2Ccr, Nanod_pswIToFtu,
    output Nanod_ird2Ftu, Nanod_ssw2Ftu,
    output Nanod_initST,
    output Nanod_Ir2Ird,
    output reg Nanod_auClkEn, 
    output reg Nanod_noSpAlign,
    output reg [2:0] Nanod_auCntrl,
    output reg Nanod_todbin,
    output reg Nanod_toIrc,
    output reg Nanod_dbl2Atl, Nanod_abl2Atl, Nanod_atl2Abl, Nanod_atl2Dbl,
    output reg Nanod_abh2Ath, Nanod_dbh2Ath,
    output reg Nanod_ath2Dbh, Nanod_ath2Abh,
    output wire Nanod_db2Aob, Nanod_ab2Aob, Nanod_au2Aob,
    output reg Nanod_aob2Ab, 
	 output wire Nanod_updSsw,
    output reg [1:0] Nanod_dobCtrl,
    output Nanod_abh2reg, Nanod_abl2reg,
    output Nanod_reg2abl, Nanod_reg2abh,
    output Nanod_dbh2reg, Nanod_dbl2reg,
    output Nanod_reg2dbl, Nanod_reg2dbh,
    output Nanod_ssp, Nanod_pchdbh, Nanod_pcldbl, Nanod_pclabl, Nanod_pchabh,
    output reg Nanod_rxh2dbh, Nanod_rxh2abh,
    output reg Nanod_dbl2rxl, 
    output reg Nanod_dbh2rxh,
    output reg Nanod_rxl2db, Nanod_rxl2ab,
    output reg Nanod_abl2rxl, Nanod_abh2rxh,
    output reg Nanod_dbh2ryh, Nanod_abh2ryh,
    output reg Nanod_ryl2db, Nanod_ryl2ab,
    output reg Nanod_ryh2dbh, Nanod_ryh2abh,
    output reg Nanod_dbl2ryl, Nanod_abl2ryl,
    output Nanod_rz,
    output Nanod_rxlDbl,
    output [2:0] Nanod_aluColumn,
    output [1:0] Nanod_aluDctrl,
    output Nanod_aluActrl,
    output Nanod_aluInit, Nanod_aluFinish,
    output reg Nanod_abd2Dcr, 
    output reg Nanod_dcr2Dbd,
    output reg Nanod_dbd2Alue, Nanod_alue2Dbd,
    output reg Nanod_dbd2Alub, 
    output reg Nanod_abd2Alub,
    output reg Nanod_alu2Dbd, 
    output reg Nanod_alu2Abd,
    output Nanod_au2Db, Nanod_au2Ab, Nanod_au2Pc,
    output Nanod_dbin2Abd, Nanod_dbin2Dbd,
    output reg Nanod_extDbh, Nanod_extAbh,
    output reg Nanod_ablAbd, Nanod_ablAbh,
    output reg Nanod_dblDbd, Nanod_dblDbh,
    output Nanod_abdIsByte,




    input enT2, enT4,
    input [UROM_WIDTH-1:0] microLatch,
    input [NANO_WIDTH-1:0] nanoLatch);

localparam NANO_IR2IRD = 67;
localparam NANO_TOIRC = 66;
localparam NANO_ALU_COL = 63;       // ALU operator column order is 63-64-65 !
localparam NANO_ALU_FI = 61;    // ALU finish-init 62-61
localparam NANO_TODBIN = 60;
localparam NANO_ALUE = 57;          // 57-59 shared with DCR control
localparam NANO_DCR = 57;           // 57-59 shared with ALUE control
localparam NANO_DOBCTRL_1 = 56;     // Input to control and permwrite
localparam NANO_LOWBYTE = 55;       // Used by MOVEP
localparam NANO_HIGHBYTE = 54;
localparam NANO_DOBCTRL_0 = 53;     // Input to control and permwrite
localparam NANO_ALU_DCTRL = 51; // 52-51 databus input mux control
localparam NANO_ALU_ACTRL = 50; // addrbus input mux control
localparam NANO_DBD2ALUB = 49;
localparam NANO_ABD2ALUB = 48;
localparam NANO_DBIN2DBD = 47;
localparam NANO_DBIN2ABD = 46;
localparam NANO_ALU2ABD = 45;
localparam NANO_ALU2DBD = 44;
localparam NANO_RZ = 43;
localparam NANO_BUSBYTE = 42;       // If *both* this set and instruction is byte sized, then bus cycle is byte sized.
localparam NANO_PCLABL = 41;
localparam NANO_RXL_DBL = 40;       // Switches RXL/RYL on DBL/ABL buses
localparam NANO_PCLDBL = 39;
localparam NANO_ABDHRECHARGE = 38;
localparam NANO_REG2ABL = 37;       // register to ABL
localparam NANO_ABL2REG = 36;       // ABL to register
localparam NANO_ABLABD = 35;
localparam NANO_DBLDBD = 34;
localparam NANO_DBL2REG = 33;       // DBL to register
localparam NANO_REG2DBL = 32;       // register to DBL
localparam NANO_ATLCTRL = 29;       // 31-29
localparam NANO_FTUCONTROL = 25;
localparam NANO_SSP = 24;
localparam NANO_RXH_DBH = 22;       // Switches RXH/RYH on DBH/ABH buses
localparam NANO_AUOUT = 20;         // 21-20
localparam NANO_AUCLKEN = 19;
localparam NANO_AUCTRL = 16;        // 18-16
localparam NANO_DBLDBH = 15;
localparam NANO_ABLABH = 14;
localparam NANO_EXT_ABH = 13;
localparam NANO_EXT_DBH = 12;
localparam NANO_ATHCTRL = 9;        // 11-9
localparam NANO_REG2ABH = 8;        // register to ABH
localparam NANO_ABH2REG = 7;        // ABH to register
localparam NANO_REG2DBH = 6;        // register to DBH
localparam NANO_DBH2REG = 5;        // DBH to register
localparam NANO_AOBCTRL = 3;        // 4-3
localparam NANO_PCH = 0;            // 1-0 PchDbh PchAbh
localparam NANO_NO_SP_ALGN = 0;     // Same bits as above when both set

localparam NANO_FTU_UPDTPEND = 1;       // Also loads FTU constant according to IRD !
localparam NANO_FTU_INIT_ST = 15;       // Set S, clear T (but not TPEND)
localparam NANO_FTU_CLRTPEND = 14;
localparam NANO_FTU_TVN = 13;
localparam NANO_FTU_ABL2PREN = 12;      // ABL => FTU & ABL => PREN. Both transfers enabled, but only one will be used depending on uroutine.
localparam NANO_FTU_SSW = 11;
localparam NANO_FTU_RSTPREN = 10;
localparam NANO_FTU_IRD = 9;
localparam NANO_FTU_2ABL = 8;
localparam NANO_FTU_RDSR = 7;
localparam NANO_FTU_INL = 6;
localparam NANO_FTU_PSWI = 5;       // Read Int Mask into FTU
localparam NANO_FTU_DBL = 4;
localparam NANO_FTU_2SR = 2;
localparam NANO_FTU_CONST = 1;

    reg [3:0] ftuCtrl;  
    
    wire [2:0] athCtrl, atlCtrl;
    assign athCtrl = nanoLatch[ NANO_ATHCTRL+2: NANO_ATHCTRL];
    assign atlCtrl = nanoLatch[ NANO_ATLCTRL+2: NANO_ATLCTRL];
    wire [1:0] aobCtrl = nanoLatch[ NANO_AOBCTRL+1:NANO_AOBCTRL];
    wire [1:0] dobCtrl = {nanoLatch[ NANO_DOBCTRL_1], nanoLatch[NANO_DOBCTRL_0]};
    
    always @( posedge Clks_clk) begin
        if( enT4) begin
            // Reverse order!
            ftuCtrl <= { nanoLatch[ NANO_FTUCONTROL+0], nanoLatch[ NANO_FTUCONTROL+1], nanoLatch[ NANO_FTUCONTROL+2], nanoLatch[ NANO_FTUCONTROL+3]} ;
                
            Nanod_auClkEn <= !nanoLatch[ NANO_AUCLKEN];
            Nanod_auCntrl <= nanoLatch[ NANO_AUCTRL+2 : NANO_AUCTRL+0];
            Nanod_noSpAlign <= (nanoLatch[ NANO_NO_SP_ALGN + 1:NANO_NO_SP_ALGN] == 2'b11);          
            Nanod_extDbh <= nanoLatch[ NANO_EXT_DBH];
            Nanod_extAbh <= nanoLatch[ NANO_EXT_ABH];
            Nanod_todbin <= nanoLatch[ NANO_TODBIN];
            Nanod_toIrc <=  nanoLatch[ NANO_TOIRC];
            
            // ablAbd is disabled on byte transfers (adbhCharge plus irdIsByte). Not sure the combination makes much sense.
            // It happens in a few cases but I don't see anything enabled on abL (or abH) section anyway.
            
            Nanod_ablAbd <= nanoLatch[ NANO_ABLABD];
            Nanod_ablAbh <= nanoLatch[ NANO_ABLABH];
            Nanod_dblDbd <= nanoLatch[ NANO_DBLDBD];
            Nanod_dblDbh <= nanoLatch[ NANO_DBLDBH];
            
            Nanod_dbl2Atl <= (atlCtrl == 3'b010);
            Nanod_atl2Dbl <= (atlCtrl == 3'b011);
            Nanod_abl2Atl <= (atlCtrl == 3'b100);
            Nanod_atl2Abl <= (atlCtrl == 3'b101);

            Nanod_aob2Ab <= (athCtrl == 3'b101);        // Used on BSER1 only
            
            Nanod_abh2Ath <= (athCtrl == 3'b001) | (athCtrl == 3'b101);
            Nanod_dbh2Ath <= (athCtrl == 3'b100);
            Nanod_ath2Dbh <= (athCtrl == 3'b110);
            Nanod_ath2Abh <= (athCtrl == 3'b011);           

            Nanod_alu2Dbd <= nanoLatch[ NANO_ALU2DBD];
            Nanod_alu2Abd <= nanoLatch[ NANO_ALU2ABD];
            
            Nanod_abd2Dcr <= (nanoLatch[ NANO_DCR+1:NANO_DCR] == 2'b11);
            Nanod_dcr2Dbd <= (nanoLatch[ NANO_DCR+2:NANO_DCR+1] == 2'b11);
            Nanod_dbd2Alue <= (nanoLatch[ NANO_ALUE+2:NANO_ALUE+1] == 2'b10);
            Nanod_alue2Dbd <= (nanoLatch[ NANO_ALUE+1:NANO_ALUE] == 2'b01);

            Nanod_dbd2Alub <= nanoLatch[ NANO_DBD2ALUB];
            Nanod_abd2Alub <= nanoLatch[ NANO_ABD2ALUB];            
            
            // Originally not latched. We better should because we transfer one cycle later, T3 instead of T1.
            Nanod_dobCtrl <= dobCtrl;
            // Nanod_adb2Dob <= (dobCtrl == 2'b10);         Nanod_dbd2Dob <= (dobCtrl == 2'b01);            Nanod_alu2Dob <= (dobCtrl == 2'b11);
                            
        end
    end
    
    // Update SSW at the start of Bus/Addr error ucode
    assign Nanod_updSsw = Nanod_aob2Ab;

    assign Nanod_updTpend = (ftuCtrl == NANO_FTU_UPDTPEND);
    assign Nanod_clrTpend = (ftuCtrl == NANO_FTU_CLRTPEND);
    assign Nanod_tvn2Ftu = (ftuCtrl == NANO_FTU_TVN);
    assign Nanod_const2Ftu = (ftuCtrl == NANO_FTU_CONST);
    assign Nanod_ftu2Dbl = (ftuCtrl == NANO_FTU_DBL) | ( ftuCtrl == NANO_FTU_INL);  
    assign Nanod_ftu2Abl = (ftuCtrl == NANO_FTU_2ABL);  
    assign Nanod_inl2psw = (ftuCtrl == NANO_FTU_INL);
    assign Nanod_pswIToFtu = (ftuCtrl == NANO_FTU_PSWI);
    assign Nanod_ftu2Sr = (ftuCtrl == NANO_FTU_2SR);
    assign Nanod_sr2Ftu = (ftuCtrl == NANO_FTU_RDSR);
    assign Nanod_ird2Ftu = (ftuCtrl == NANO_FTU_IRD);       // Used on bus/addr error
    assign Nanod_ssw2Ftu = (ftuCtrl == NANO_FTU_SSW);
    assign Nanod_initST = (ftuCtrl == NANO_FTU_INL) | (ftuCtrl == NANO_FTU_CLRTPEND) | (ftuCtrl == NANO_FTU_INIT_ST);
    assign Nanod_abl2Pren = (ftuCtrl == NANO_FTU_ABL2PREN);
    assign Nanod_updPren = (ftuCtrl == NANO_FTU_RSTPREN);
    
    assign Nanod_Ir2Ird = nanoLatch[ NANO_IR2IRD];

    // ALU control better latched later after combining with IRD decoding
        
    assign Nanod_aluDctrl = nanoLatch[ NANO_ALU_DCTRL+1 : NANO_ALU_DCTRL];
    assign Nanod_aluActrl = nanoLatch[ NANO_ALU_ACTRL];
    assign Nanod_aluColumn = { nanoLatch[ NANO_ALU_COL], nanoLatch[ NANO_ALU_COL+1], nanoLatch[ NANO_ALU_COL+2]};
    wire [1:0] aluFinInit = nanoLatch[ NANO_ALU_FI+1:NANO_ALU_FI];
    assign Nanod_aluFinish = (aluFinInit == 2'b10);
    assign Nanod_aluInit = (aluFinInit == 2'b01);

    // FTU 2 CCR encoded as both ALU Init and ALU Finish set.
    // In theory this encoding allows writes to CCR without writing to SR
    // But FTU 2 CCR and to SR are both set together at nanorom.
    assign Nanod_ftu2Ccr = ( aluFinInit == 2'b11);

    assign Nanod_abdIsByte = nanoLatch[ NANO_ABDHRECHARGE];
    
    // Not being latched on T4 creates non case warning!
    assign Nanod_au2Db = (nanoLatch[ NANO_AUOUT + 1: NANO_AUOUT] == 2'b01);
    assign Nanod_au2Ab = (nanoLatch[ NANO_AUOUT + 1: NANO_AUOUT] == 2'b10);
    assign Nanod_au2Pc = (nanoLatch[ NANO_AUOUT + 1: NANO_AUOUT] == 2'b11);
    
    assign Nanod_db2Aob = (aobCtrl == 2'b10);
    assign Nanod_ab2Aob = (aobCtrl == 2'b01);
    assign Nanod_au2Aob = (aobCtrl == 2'b11);
    
    assign Nanod_dbin2Abd = nanoLatch[ NANO_DBIN2ABD];
    assign Nanod_dbin2Dbd = nanoLatch[ NANO_DBIN2DBD];
    
    assign Nanod_permStart = (| aobCtrl);
    assign Nanod_isWrite  = ( | dobCtrl);
    assign Nanod_waitBusFinish = nanoLatch[ NANO_TOIRC] | nanoLatch[ NANO_TODBIN] | Nanod_isWrite;
    assign Nanod_busByte = nanoLatch[ NANO_BUSBYTE];
    
    assign Nanod_noLowByte = nanoLatch[ NANO_LOWBYTE];
    assign Nanod_noHighByte = nanoLatch[ NANO_HIGHBYTE];    
            
    // Not registered. Register at T4 after combining
    // Might be better to remove all those and combine here instead of at execution unit !!
    assign Nanod_abl2reg = nanoLatch[ NANO_ABL2REG];
    assign Nanod_abh2reg = nanoLatch[ NANO_ABH2REG];
    assign Nanod_dbl2reg = nanoLatch[ NANO_DBL2REG];
    assign Nanod_dbh2reg = nanoLatch[ NANO_DBH2REG];
    assign Nanod_reg2dbl = nanoLatch[ NANO_REG2DBL];
    assign Nanod_reg2dbh = nanoLatch[ NANO_REG2DBH];
    assign Nanod_reg2abl = nanoLatch[ NANO_REG2ABL];
    assign Nanod_reg2abh = nanoLatch[ NANO_REG2ABH];
    
    assign Nanod_ssp = nanoLatch[ NANO_SSP];
    
    assign Nanod_rz = nanoLatch[ NANO_RZ];
    
    // Actually DTL can't happen on PC relative mode. See IR decoder.
    
    wire dtldbd = 1'b0;
    wire dthdbh = 1'b0;
    wire dtlabd = 1'b0;
    wire dthabh = 1'b0;
    
    wire dblSpecial = Nanod_pcldbl | dtldbd;
    wire dbhSpecial = Nanod_pchdbh | dthdbh;
    wire ablSpecial = Nanod_pclabl | dtlabd;
    wire abhSpecial = Nanod_pchabh | dthabh;
            
    //
    // Combine with IRD decoding
    // Careful that IRD is updated only on T1! All output depending on IRD must be latched on T4!
    //
    
    // PC used instead of RY on PC relative instuctions
    
    assign Nanod_rxlDbl = nanoLatch[ NANO_RXL_DBL];
    wire isPcRel = Irdecod_isPcRel & !Nanod_rz;
    wire pcRelDbl = isPcRel & !nanoLatch[ NANO_RXL_DBL];
    wire pcRelDbh = isPcRel & !nanoLatch[ NANO_RXH_DBH];
    wire pcRelAbl = isPcRel & nanoLatch[ NANO_RXL_DBL];
    wire pcRelAbh = isPcRel & nanoLatch[ NANO_RXH_DBH];
    
    assign Nanod_pcldbl = nanoLatch[ NANO_PCLDBL] | pcRelDbl;
    assign Nanod_pchdbh = (nanoLatch[ NANO_PCH+1:NANO_PCH] == 2'b01) | pcRelDbh;
    
    assign Nanod_pclabl = nanoLatch[ NANO_PCLABL] | pcRelAbl;
    assign Nanod_pchabh = (nanoLatch[ NANO_PCH+1:NANO_PCH] == 2'b10) | pcRelAbh;

    // Might be better not to register these signals to allow latching RX/RY mux earlier!
    // But then must latch Irdecod_isPcRel on T3!

    always @( posedge Clks_clk) begin
        if( enT4) begin
            Nanod_rxl2db <= Nanod_reg2dbl & !dblSpecial & nanoLatch[ NANO_RXL_DBL];
            Nanod_rxl2ab <= Nanod_reg2abl & !ablSpecial & !nanoLatch[ NANO_RXL_DBL];
            
            Nanod_dbl2rxl <= Nanod_dbl2reg & !dblSpecial & nanoLatch[ NANO_RXL_DBL];    
            Nanod_abl2rxl <= Nanod_abl2reg & !ablSpecial & !nanoLatch[ NANO_RXL_DBL];   

            Nanod_rxh2dbh <= Nanod_reg2dbh & !dbhSpecial & nanoLatch[ NANO_RXH_DBH];            
            Nanod_rxh2abh <= Nanod_reg2abh & !abhSpecial & !nanoLatch[ NANO_RXH_DBH];           
                
            Nanod_dbh2rxh <= Nanod_dbh2reg & !dbhSpecial & nanoLatch[ NANO_RXH_DBH];
            Nanod_abh2rxh <= Nanod_abh2reg & !abhSpecial & !nanoLatch[ NANO_RXH_DBH];   

            Nanod_dbh2ryh <= Nanod_dbh2reg & !dbhSpecial & !nanoLatch[ NANO_RXH_DBH];
            Nanod_abh2ryh <= Nanod_abh2reg & !abhSpecial & nanoLatch[ NANO_RXH_DBH];    

            Nanod_dbl2ryl <= Nanod_dbl2reg & !dblSpecial & !nanoLatch[ NANO_RXL_DBL];   
            Nanod_abl2ryl <= Nanod_abl2reg & !ablSpecial & nanoLatch[ NANO_RXL_DBL];    

            Nanod_ryl2db <= Nanod_reg2dbl & !dblSpecial & !nanoLatch[ NANO_RXL_DBL];
            Nanod_ryl2ab <= Nanod_reg2abl & !ablSpecial & nanoLatch[ NANO_RXL_DBL];

            Nanod_ryh2dbh <= Nanod_reg2dbh & !dbhSpecial & !nanoLatch[ NANO_RXH_DBH];           
            Nanod_ryh2abh <= Nanod_reg2abh & !abhSpecial & nanoLatch[ NANO_RXH_DBH];                    
        end
        
        // Originally isTas only delayed on T2 (and seems only a late mask rev fix)
        // Better latch the combination on T4
        if( enT4)
            Nanod_isRmc <= Irdecod_isTas & nanoLatch[ NANO_BUSBYTE];
    end
            
    
endmodule

//
// IRD execution decoder. Complements nano code decoder
//
// IRD updated on T1, while ncode still executing. To avoid using the next IRD,
// decoded signals must be registered on T3, or T4 before using them.
//
module irdDecode( input [15:0] ird,
    output            Irdecod_isPcRel,
    output            Irdecod_isTas,
    output     reg    Irdecod_implicitSp,
    output            Irdecod_toCcr,
    output            Irdecod_rxIsDt, 
    output            Irdecod_ryIsDt,
    output            Irdecod_rxIsUsp,
    output     reg    Irdecod_rxIsMovem,
    output            Irdecod_movemPreDecr,
    output     reg    Irdecod_isByte,
    output     wire   Irdecod_isMovep,
    output     [2:0]  Irdecod_rx,
    output     [2:0]  Irdecod_ry,
    output     reg    Irdecod_rxIsAreg,
    output     reg    Irdecod_ryIsAreg,
    output     [15:0] Irdecod_ftuConst,
    output reg [ 5:0] Irdecod_macroTvn,
    output            Irdecod_inhibitCcr
    );

    wire [3:0] line = ird[15:12];
    wire [15:0] lineOnehot;

    // This can be registered and pipelined from the IR decoder !
    onehotEncoder4 irdLines( line, lineOnehot);
    
    wire isRegShift = (lineOnehot['he]) & (ird[7:6] != 2'b11);
    wire isDynShift = isRegShift & ird[5];
                    
    assign Irdecod_isPcRel = (& ird[ 5:3]) & ~isDynShift & !ird[2] & ird[1];        
    assign Irdecod_isTas = lineOnehot[4] & (ird[11:6] == 6'b101011);
    
    assign Irdecod_rx = ird[11:9];
    assign Irdecod_ry = ird[ 2:0];

    wire isPreDecr = (ird[ 5:3] == 3'b100);
    wire eaAreg = (ird[5:3] == 3'b001);
        
    // rx is A or D
    // movem
    always @* begin
        case( 1'b1)
        lineOnehot[1],
        lineOnehot[2],
        lineOnehot[3]:
                    // MOVE: RX always Areg except if dest mode is Dn 000
                    Irdecod_rxIsAreg = (| ird[8:6]);

        lineOnehot[4]:      Irdecod_rxIsAreg = (& ird[8:6]);        // not CHK (LEA)

        lineOnehot['h8]:    Irdecod_rxIsAreg = eaAreg & ird[8] & ~ird[7];   // SBCD
        lineOnehot['hc]:    Irdecod_rxIsAreg = eaAreg & ird[8] & ~ird[7];   // ABCD/EXG An,An               
        
        lineOnehot['h9],
        lineOnehot['hb],
        lineOnehot['hd]:    Irdecod_rxIsAreg =
                            (ird[7] & ird[6]) |                             // SUBA/CMPA/ADDA
                            (eaAreg & ird[8] & (ird[7:6] != 2'b11));        // SUBX/CMPM/ADDX       
        default:
                Irdecod_rxIsAreg = Irdecod_implicitSp;
        endcase
    end 

    // RX is movem
    always @* begin
        Irdecod_rxIsMovem = lineOnehot[4] & ~ird[8] & ~Irdecod_implicitSp;
    end
    assign Irdecod_movemPreDecr = Irdecod_rxIsMovem & isPreDecr;
    
    // RX is DT.
    // but SSP explicit or pc explicit has higher priority!
    // addq/subq (scc & dbcc also, but don't use rx)
    // Immediate including static bit
    assign Irdecod_rxIsDt = lineOnehot[5] | (lineOnehot[0] & ~ird[8]);
    
    // RX is USP
    assign Irdecod_rxIsUsp = lineOnehot[4] & (ird[ 11:4] == 8'he6);
    
    // RY is DT
    // rz or PC explicit has higher priority
    
    wire eaImmOrAbs = (ird[5:3] == 3'b111) & ~ird[1];
    assign Irdecod_ryIsDt = eaImmOrAbs & ~isRegShift;
        
    // RY is Address register
    reg eaIsAreg;
    always @* begin
        
        // On most cases RY is Areg expect if mode is 000 (DATA REG) or 111 (IMM, ABS,PC REL)
        eaIsAreg = (ird[5:3] != 3'b000) & (ird[5:3] != 3'b111);
        
        case( 1'b1)
                // MOVE: RY always Areg expect if mode is 000 (DATA REG) or 111 (IMM, ABS,PC REL)
                // Most lines, including misc line 4, also.
        default:        Irdecod_ryIsAreg = eaIsAreg;

        lineOnehot[5]:  // DBcc is an exception
                        Irdecod_ryIsAreg = eaIsAreg & (ird[7:3] != 5'b11001);

        lineOnehot[6],
        lineOnehot[7]:  Irdecod_ryIsAreg = 1'b0;

        lineOnehot['he]:
                        Irdecod_ryIsAreg = ~isRegShift;
        endcase
    end 

    // Byte sized instruction
        
    // Original implementation sets this for some instructions that aren't really byte size
    // but doesn't matter because they don't have a byte transfer enabled at nanocode, such as MOVEQ
        
    wire xIsScc = (ird[7:6] == 2'b11) & (ird[5:3] != 3'b001); 
    wire xStaticMem = (ird[11:8] == 4'b1000) & (ird[5:4] == 2'b00);     // Static bit to mem
    always @* begin
        case( 1'b1)
        lineOnehot[0]:
                Irdecod_isByte = 
                ( ird[8] & (ird[5:4] != 2'b00)                  ) | // Dynamic bit to mem
                ( (ird[11:8] == 4'b1000) & (ird[5:4] != 2'b00)  ) | // Static bit to mem
                ( (ird[8:7] == 2'b10) & (ird[5:3] == 3'b001)    ) | // Movep from mem only! For byte mux
                ( (ird[8:6] == 3'b000) & !xStaticMem );             // Immediate byte
                                
        lineOnehot[1]:          Irdecod_isByte = 1'b1;      // MOVE.B
    
        
        lineOnehot[4]:          Irdecod_isByte = (ird[7:6] == 2'b00) | Irdecod_isTas;       
        lineOnehot[5]:          Irdecod_isByte = (ird[7:6] == 2'b00) | xIsScc;
        
        lineOnehot[8],
        lineOnehot[9],
        lineOnehot['hb],
        lineOnehot['hc],
        lineOnehot['hd],
        lineOnehot['he]:        Irdecod_isByte = (ird[7:6] == 2'b00);
        
        default:                Irdecod_isByte = 1'b0;
        endcase
    end 
    
    // Need it for special byte size. Bus is byte, but whole register word is modified.
    assign Irdecod_isMovep = lineOnehot[0] & ird[8] & eaAreg;
    
    
    // rxIsSP implicit use of RX for actual SP transfer
    //
    // This logic is simple and will include some instructions that don't actually reference SP.
    // But doesn't matter as long as they don't perform any RX transfer.
    
    always @* begin
        case( 1'b1)
        lineOnehot[6]:      Irdecod_implicitSp = (ird[11:8] == 4'b0001);        // BSR
        lineOnehot[4]:
            // Misc like RTS, JSR, etc
            Irdecod_implicitSp = (ird[11:8] == 4'b1110) | (ird[11:6] == 6'b1000_01);
        default:            Irdecod_implicitSp = 1'b0;
        endcase
    end
    
    // Modify CCR (and not SR)
    // Probably overkill !! Only needs to distinguish SR vs CCR
    // RTR, MOVE to CCR, xxxI to CCR
    assign Irdecod_toCcr =  ( lineOnehot[4] & ((ird[11:0] == 12'he77) | (ird[11:6] == 6'b010011)) ) |
                            ( lineOnehot[0] & (ird[8:6] == 3'b000));
    
    // FTU constants
    // This should not be latched on T3/T4. Latch on T2 or not at all. FTU needs it on next T3.
    // Note: Reset instruction gets constant from ALU not from FTU!
    reg [15:0] ftuConst;
    wire [3:0] zero28 = (ird[11:9] == 0) ? 4'h8 : { 1'b0, ird[11:9]};       // xltate 0,1-7 into 8,1-7

    always @* begin
        case( 1'b1)
        lineOnehot[6],                                                      // Bcc short
        lineOnehot[7]:      ftuConst = { { 8{ ird[ 7]}}, ird[ 7:0] };       // MOVEQ
        
        lineOnehot['h5],                                                    // addq/subq/static shift double check this
        lineOnehot['he]:    ftuConst = { 12'b0, zero28};
        
        // MULU/MULS DIVU/DIVS
        lineOnehot['h8],
        lineOnehot['hc]:    ftuConst = 16'h0f;

        lineOnehot[4]:      ftuConst = 16'h80;                              // TAS

        default:            ftuConst = 1'b0;
        endcase 
    end 
    assign Irdecod_ftuConst = ftuConst;
    
    //
    // TRAP Vector # for group 2 exceptions
    //
    
    always @* begin
        if( lineOnehot[4]) begin
            case ( ird[6:5])
            2'b00,2'b01:    Irdecod_macroTvn = 6;                   // CHK
            2'b11:          Irdecod_macroTvn = 7;                   // TRAPV
            2'b10:          Irdecod_macroTvn = {2'b10, ird[3:0]};   // TRAP
            endcase
        end
        else
                            Irdecod_macroTvn = 5;                   // Division by zero
    end
    
    
    wire eaAdir = (ird[ 5:3] == 3'b001);
    wire size11 = ird[7] & ird[6];
    
    // Opcodes variants that don't affect flags
    // ADDA/SUBA ADDQ/SUBQ MOVEA

    assign Irdecod_inhibitCcr =
        ( (lineOnehot[9] | lineOnehot['hd]) & size11) |             // ADDA/SUBA
        ( lineOnehot[5] & eaAdir) |                                 // ADDQ/SUBQ to An (originally checks for line[4] as well !?)
        ( (lineOnehot[2] | lineOnehot[3]) & ird[8:6] == 3'b001);    // MOVEA
        
endmodule



/*
 Execution unit

 Executes register transfers set by the microcode. Originally through a set of bidirectional buses.
 Most sources are available at T3, but DBIN only at T4! CCR also might be updated at T4, but it is not connected to these buses.
 We mux at T1 and T2, then transfer to the destination at T3. The exception is AOB that need to be updated earlier.

*/

module excUnit( 
    input Clks_clk,
    input Clks_extReset,         // External sync reset on emulated system
    input Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
    input Clks_enPhi1,
    input Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
    input enT1, enT2, enT3, enT4,

    input Nanod_permStart,
    input Nanod_waitBusFinish,
    input Nanod_isWrite,
    input Nanod_busByte,
    input Nanod_isRmc,
    input Nanod_noLowByte, Nanod_noHighByte,
    input Nanod_updTpend, Nanod_clrTpend,
    input Nanod_tvn2Ftu, Nanod_const2Ftu,
    input Nanod_ftu2Dbl, Nanod_ftu2Abl,
    input Nanod_abl2Pren, Nanod_updPren,
    input Nanod_inl2psw, Nanod_ftu2Sr, Nanod_sr2Ftu, Nanod_ftu2Ccr, Nanod_pswIToFtu,
    input Nanod_ird2Ftu, Nanod_ssw2Ftu,
    input Nanod_initST,
    input Nanod_Ir2Ird,
    input Nanod_auClkEn, Nanod_noSpAlign,
    input [2:0] Nanod_auCntrl,
    input Nanod_todbin, Nanod_toIrc,
    input Nanod_dbl2Atl, Nanod_abl2Atl, Nanod_atl2Abl, Nanod_atl2Dbl,
    input Nanod_abh2Ath, Nanod_dbh2Ath,
    input Nanod_ath2Dbh, Nanod_ath2Abh,
    input Nanod_db2Aob, Nanod_ab2Aob, Nanod_au2Aob,
    input Nanod_aob2Ab, Nanod_updSsw,
    input [1:0] Nanod_dobCtrl,
    input Nanod_abh2reg, Nanod_abl2reg,
    input Nanod_reg2abl, Nanod_reg2abh,
    input Nanod_dbh2reg, Nanod_dbl2reg,
    input Nanod_reg2dbl, Nanod_reg2dbh,
    input Nanod_ssp, Nanod_pchdbh, Nanod_pcldbl, Nanod_pclabl, Nanod_pchabh,
    input Nanod_rxh2dbh, Nanod_rxh2abh,
    input Nanod_dbl2rxl, Nanod_dbh2rxh,
    input Nanod_rxl2db, Nanod_rxl2ab,
    input Nanod_abl2rxl, Nanod_abh2rxh,
    input Nanod_dbh2ryh, Nanod_abh2ryh,
    input Nanod_ryl2db, Nanod_ryl2ab,
    input Nanod_ryh2dbh, Nanod_ryh2abh,
    input Nanod_dbl2ryl, Nanod_abl2ryl,
    input Nanod_rz,
    input Nanod_rxlDbl,
    input [2:0] Nanod_aluColumn,
    input [1:0] Nanod_aluDctrl,
    input Nanod_aluActrl,
    input Nanod_aluInit, Nanod_aluFinish,
    input Nanod_abd2Dcr, Nanod_dcr2Dbd,
    input Nanod_dbd2Alue, Nanod_alue2Dbd,
    input Nanod_dbd2Alub, Nanod_abd2Alub,
    input Nanod_alu2Dbd, Nanod_alu2Abd,
    input Nanod_au2Db, Nanod_au2Ab, Nanod_au2Pc,
    input Nanod_dbin2Abd, Nanod_dbin2Dbd,
    input Nanod_extDbh, Nanod_extAbh,
    input Nanod_ablAbd, Nanod_ablAbh,
    input Nanod_dblDbd, Nanod_dblDbh,
    input Nanod_abdIsByte,


    input        Irdecod_isPcRel,
    input        Irdecod_isTas,
    input        Irdecod_implicitSp,
    input        Irdecod_toCcr,
    input        Irdecod_rxIsDt, 
    input        Irdecod_ryIsDt,
    input        Irdecod_rxIsUsp,
    input        Irdecod_rxIsMovem,
    input        Irdecod_movemPreDecr,
    input        Irdecod_isByte,
    input        Irdecod_isMovep,
    input [2:0]  Irdecod_rx,
    input [2:0]  Irdecod_ry,
    input        Irdecod_rxIsAreg,
    input        Irdecod_ryIsAreg,
    input [15:0] Irdecod_ftuConst,
    input [ 5:0] Irdecod_macroTvn,
    input        Irdecod_inhibitCcr,    


    input [15:0] Ird,           // ALU row (and others) decoder needs it    
    input pswS,
    input [15:0] ftu,
    input [15:0] iEdb,
    
    output wire [7:0] ccr,
    output [15:0] alue,
    
    output prenEmpty, au05z,
    output reg dcr4,
	 output wire ze,
    output wire aob0,
    output [15:0] AblOut,
    output wire [15:0] Irc,
    output wire [15:0] oEdb,
    output wire [23:1] eab);

localparam REG_USP = 15;
localparam REG_SSP = 16;
localparam REG_DT = 17;

    // Register file
    reg [15:0] regs68L[0:18]; //CAMBIO NEURO
    reg [15:0] regs68H[0:18]; //CAMBIO NEURO

// synthesis translate off
    /*
        It is bad practice to initialize simulation registers that the hardware doesn't.
        There is risk that simulation would be different than the real hardware. But in this case is the other way around.
        Some ROM uses something like sub.l An,An at powerup which clears the register
        Simulator power ups the registers with 1'bX, as they are really undetermined at the real hardware.
        But the simulator doesn't realize (it can't) that the same value is substracting from itself,
        and that the result should be zero even when it's 1'bX - 1'bX.
    */
    
    initial begin
        for( int i = 0; i < 18; i++) begin
            regs68L[i] <= 1'b0;
            regs68H[i] <= 1'b0;
        end
    end
    
    // For simulation display only
    wire [31:0] SSP = { regs68H[REG_SSP], regs68L[REG_SSP]};
    
// synthesis translate on
    

    wire [15:0] aluOut;
    wire [15:0] dbin;
    reg [15:0] dcrOutput;

    reg [15:0] PcL, PcH;

    reg [31:0] auReg, aob;

    reg [15:0] Ath, Atl;

    // Bus execution
    reg [15:0] Dbl, Dbh;
    reg [15:0] Abh, Abl;
    reg [15:0] Abd, Dbd;
    
    assign AblOut = Abl;
    assign au05z = (~| auReg[5:0]);
    
    reg [15:0] dblMux, dbhMux;
    reg [15:0] abhMux, ablMux;
    reg [15:0] abdMux, dbdMux;
    
    reg abdIsByte;
        
    reg Pcl2Dbl, Pch2Dbh;
    reg Pcl2Abl, Pch2Abh;
    
    
    // RX RY muxes  
    // RX and RY actual registers
    reg [4:0] actualRx, actualRy;
    reg [3:0] movemRx;
    reg byteNotSpAlign;           // Byte instruction and no sp word align
    
    // IRD decoded signals must be latched. See comments on decoder
    // But nanostore decoding can't be latched before T4.
    //
    // If we need this earlier we can register IRD decode on T3 and use nano async

    reg [4:0] rxMux, ryMux;
    reg [3:0] rxReg, ryReg;
    reg rxIsSp, ryIsSp;
    reg rxIsAreg, ryIsAreg;
    
    always @* begin
    
        // Unique IF !!
        if( Nanod_ssp) begin
            rxMux = REG_SSP;
            rxIsSp = 1'b1;
            rxReg = 1'bX;
        end
        else if( Irdecod_rxIsUsp) begin
            rxMux = REG_USP;
            rxIsSp = 1'b1;
            rxReg = 1'bX;
        end
        else if( Irdecod_rxIsDt & !Irdecod_implicitSp) begin
            rxMux = REG_DT;
            rxIsSp = 1'b0;
            rxReg = 1'bX;
        end
        else begin
            if( Irdecod_implicitSp)
                rxReg = 15;
            else if( Irdecod_rxIsMovem)
                rxReg = movemRx;
            else
                rxReg = { Irdecod_rxIsAreg, Irdecod_rx};
                
            if( (& rxReg)) begin
                rxMux = pswS ? REG_SSP : 15;
                rxIsSp = 1'b1;
            end
            else begin
                rxMux = { 1'b0, rxReg};
                rxIsSp = 1'b0;
            end
        end

        // RZ has higher priority!      
        if( Irdecod_ryIsDt & !Nanod_rz) begin
            ryMux = REG_DT;
            ryIsSp = 1'b0;
            ryReg = 1'bX;
        end
        else begin
            ryReg = Nanod_rz ? Irc[15:12] : {Irdecod_ryIsAreg, Irdecod_ry};
            ryIsSp = (& ryReg);
            if( ryIsSp & pswS)          // No implicit SP on RY
                ryMux = REG_SSP;
            else
                ryMux = { 1'b0, ryReg};
        end
                    
    end 
    
    always @( posedge Clks_clk) begin
        if( enT4) begin
            byteNotSpAlign <= Irdecod_isByte & ~(Nanod_rxlDbl ? rxIsSp : ryIsSp);
                
            actualRx <= rxMux;
            actualRy <= ryMux;
            
            rxIsAreg <= rxIsSp | rxMux[3];
            ryIsAreg <= ryIsSp | ryMux[3];          
        end
        
        if( enT4)
            abdIsByte <= Nanod_abdIsByte & Irdecod_isByte;
    end
            
    // Set RX/RY low word to which bus segment is connected.
        
    wire ryl2Abl = Nanod_ryl2ab & (ryIsAreg | Nanod_ablAbd);
    wire ryl2Abd = Nanod_ryl2ab & (~ryIsAreg | Nanod_ablAbd);
    wire ryl2Dbl = Nanod_ryl2db & (ryIsAreg | Nanod_dblDbd);
    wire ryl2Dbd = Nanod_ryl2db & (~ryIsAreg | Nanod_dblDbd);

    wire rxl2Abl = Nanod_rxl2ab & (rxIsAreg | Nanod_ablAbd);
    wire rxl2Abd = Nanod_rxl2ab & (~rxIsAreg | Nanod_ablAbd);
    wire rxl2Dbl = Nanod_rxl2db & (rxIsAreg | Nanod_dblDbd);
    wire rxl2Dbd = Nanod_rxl2db & (~rxIsAreg | Nanod_dblDbd);
    
    // Buses. Main mux
    
    reg abhIdle, ablIdle, abdIdle;
    reg dbhIdle, dblIdle, dbdIdle;
    
    always @* begin
        {abhIdle, ablIdle, abdIdle} = 1'b0;
        {dbhIdle, dblIdle, dbdIdle} = 1'b0;

        case( 1'b1)
        ryl2Dbd:                dbdMux = regs68L[ actualRy];
        rxl2Dbd:                dbdMux = regs68L[ actualRx];
        Nanod_alue2Dbd:         dbdMux = alue;
        Nanod_dbin2Dbd:         dbdMux = dbin;
        Nanod_alu2Dbd:          dbdMux = aluOut;
        Nanod_dcr2Dbd:          dbdMux = dcrOutput;
        default: begin          dbdMux = 1'bX;    dbdIdle = 1'b1;             end
        endcase
    
        case( 1'b1)
        rxl2Dbl:                dblMux = regs68L[ actualRx];
        ryl2Dbl:                dblMux = regs68L[ actualRy];
        Nanod_ftu2Dbl:          dblMux = ftu;
        Nanod_au2Db:            dblMux = auReg[15:0];
        Nanod_atl2Dbl:          dblMux = Atl;
        Pcl2Dbl:                dblMux = PcL;
        default: begin          dblMux = 1'bX;    dblIdle = 1'b1;             end
        endcase
            
        case( 1'b1)
        Nanod_rxh2dbh:          dbhMux = regs68H[ actualRx];
        Nanod_ryh2dbh:          dbhMux = regs68H[ actualRy];
        Nanod_au2Db:            dbhMux = auReg[31:16];
        Nanod_ath2Dbh:          dbhMux = Ath;
        Pch2Dbh:                dbhMux = PcH;
        default: begin          dbhMux = 1'bX;    dbhIdle = 1'b1;             end
        endcase

        case( 1'b1)
        ryl2Abd:                abdMux = regs68L[ actualRy];
        rxl2Abd:                abdMux = regs68L[ actualRx];
        Nanod_dbin2Abd:         abdMux = dbin;
        Nanod_alu2Abd:          abdMux = aluOut;
        default: begin          abdMux = 1'bX;    abdIdle = 1'b1;             end
        endcase

        case( 1'b1)
        Pcl2Abl:                ablMux = PcL;
        rxl2Abl:                ablMux = regs68L[ actualRx];
        ryl2Abl:                ablMux = regs68L[ actualRy];
        Nanod_ftu2Abl:          ablMux = ftu;
        Nanod_au2Ab:            ablMux = auReg[15:0];
        Nanod_aob2Ab:           ablMux = aob[15:0];
        Nanod_atl2Abl:          ablMux = Atl;
        default: begin          ablMux = 1'bX;    ablIdle = 1'b1;             end
        endcase
            
        case( 1'b1)     
        Pch2Abh:                abhMux = PcH;
        Nanod_rxh2abh:          abhMux = regs68H[ actualRx];
        Nanod_ryh2abh:          abhMux = regs68H[ actualRy];
        Nanod_au2Ab:            abhMux = auReg[31:16];
        Nanod_aob2Ab:           abhMux = aob[31:16];
        Nanod_ath2Abh:          abhMux = Ath;
        default: begin          abhMux = 1'bX;    abhIdle = 1'b1;             end
        endcase
            
    end
    
    // Source starts driving the bus on T1. Bus holds data until end of T3. Destination latches at T3.

    // These registers store the first level mux, without bus interconnections.
    // Even when this uses almost to 100 registers, it saves a lot of comb muxing and it is much faster.
    reg [15:0] preAbh, preAbl, preAbd;
    reg [15:0] preDbh, preDbl, preDbd;
    
    always @( posedge Clks_clk) begin

        // Register first level mux at T1       
        if( enT1) begin
            {preAbh, preAbl, preAbd} <= { abhMux, ablMux, abdMux};
            {preDbh, preDbl, preDbd} <= { dbhMux, dblMux, dbdMux};          
        end
        
        // Process bus interconnection at T2. Many combinations only used on DIV
        // We use a simple method. If a specific bus segment is not driven we know that it should get data from a neighbour segment.
        // In some cases this is not true and the segment is really idle without any destination. But then it doesn't matter.
        
        if( enT2) begin
            if( Nanod_extAbh)
                Abh <= { 16{ ablIdle ? preAbd[ 15] : preAbl[ 15] }};
            else if( abhIdle)
                Abh <= ablIdle ? preAbd : preAbl;
            else
                Abh <= preAbh;

            if( ~ablIdle)
                Abl <= preAbl;
            else
                Abl <= Nanod_ablAbh ? preAbh : preAbd;

            Abd <= ~abdIdle ? preAbd : ablIdle ? preAbh : preAbl;

            if( Nanod_extDbh)
                Dbh <= { 16{ dblIdle ? preDbd[ 15] : preDbl[ 15] }};
            else if( dbhIdle)
                Dbh <= dblIdle ? preDbd : preDbl;
            else
                Dbh <= preDbh;

            if( ~dblIdle)
                Dbl <= preDbl;
            else
                Dbl <= Nanod_dblDbh ? preDbh : preDbd;

            Dbd <= ~dbdIdle ? preDbd: dblIdle ? preDbh : preDbl;
            
            /*
            Dbl <= dblMux;          Dbh <= dbhMux;
            Abd <= abdMux;          Dbd <= dbdMux;
            Abh <= abhMux;          Abl <= ablMux; */
        end
    end

    // AOB
    //
    // Originally change on T1. We do on T2, only then the output is enabled anyway.
    //
    // AOB[0] is used for address error. But even when raises on T1, seems not actually used until T2 or possibly T3.
    // It is used on T1 when deasserted at the BSER exception ucode. Probably deassertion timing is not critical. 
    // But in that case (at BSER), AOB is loaded from AU, so we can safely transfer on T1.

    // We need to take directly from first level muxes that are updated and T1
            
    wire au2Aob = Nanod_au2Aob | (Nanod_au2Db & Nanod_db2Aob);
    
    always @( posedge Clks_clk) begin
        // UNIQUE IF !
        
        if( enT1 & au2Aob)      // From AU we do can on T1
            aob <= auReg;
        else if( enT2) begin
            if( Nanod_db2Aob)
                aob <= { preDbh, ~dblIdle ? preDbl : preDbd};
            else if( Nanod_ab2Aob)
                aob <= { preAbh, ~ablIdle ? preAbl : preAbd};
        end
    end

    assign eab = aob[23:1];
    assign aob0 = aob[0];
                
    // AU
    reg [31:0] auInpMux;

    // `ifdef ALW_COMB_BUG
    // Old Modelsim bug. Doesn't update ouput always. Need excplicit sensitivity list !?
    // always @( Nanod_auCntrl) begin
    
    always @* begin
        case( Nanod_auCntrl)
        3'b000:     auInpMux = 0;
        3'b001:     auInpMux = byteNotSpAlign | Nanod_noSpAlign ? 1 : 2;        // +1/+2
        3'b010:     auInpMux = -4;
        3'b011:     auInpMux = { Abh, Abl};
        3'b100:     auInpMux = 2;
        3'b101:     auInpMux = 4;
        3'b110:     auInpMux = -2;
        3'b111:     auInpMux = byteNotSpAlign | Nanod_noSpAlign ? -1 : -2;  // -1/-2
        default:    auInpMux = 1'bX;
        endcase
    end

    // Simulation problem
    // Sometimes (like in MULM1) DBH is not set. AU is used in these cases just as a 6 bits counter testing if bits 5-0 are zero.
    // But when adding something like 32'hXXXX0000, the simulator (incorrectly) will set *all the 32 bits* of the result as X.

// synthesis translate_off 
    `define SIMULBUGX32 1
    wire [16:0] aulow = Dbl + auInpMux[15:0];
    wire [31:0] auResult = {Dbh + auInpMux[31:16] + aulow[16], aulow[15:0]};
// synthesis translate_on

    always @( posedge Clks_clk) begin
        if( Clks_pwrUp)
            auReg <= 1'b0;
        else if( enT3 & Nanod_auClkEn)
            `ifdef SIMULBUGX32
                auReg <= auResult;
            `else
                auReg <= { Dbh, Dbl } + auInpMux;
            `endif
    end
    
    
    // Main A/D registers
    
    always @( posedge Clks_clk) begin
        if( enT3) begin
            if( Nanod_dbl2rxl | Nanod_abl2rxl) begin
                if( ~rxIsAreg) begin
                    if( Nanod_dbl2rxl)          regs68L[ actualRx] <= Dbd;
                    else if( abdIsByte)         regs68L[ actualRx][7:0] <= Abd[7:0];
                    else                        regs68L[ actualRx] <= Abd;
                end
                else
                    regs68L[ actualRx] <= Nanod_dbl2rxl ? Dbl : Abl;
            end
                
            if( Nanod_dbl2ryl | Nanod_abl2ryl) begin
                if( ~ryIsAreg) begin
                    if( Nanod_dbl2ryl)          regs68L[ actualRy] <= Dbd;
                    else if( abdIsByte)         regs68L[ actualRy][7:0] <= Abd[7:0];
                    else                        regs68L[ actualRy] <= Abd;              
                end
                else
                    regs68L[ actualRy] <= Nanod_dbl2ryl ? Dbl : Abl;
            end
            
            // High registers are easier. Both A & D on the same buses, and not byte ops.
            if( Nanod_dbh2rxh | Nanod_abh2rxh)
                regs68H[ actualRx] <= Nanod_dbh2rxh ? Dbh : Abh;
            if( Nanod_dbh2ryh | Nanod_abh2ryh)
                regs68H[ actualRy] <= Nanod_dbh2ryh ? Dbh : Abh;
                
        end 
    end
        
    // PC & AT
    reg dbl2Pcl, dbh2Pch, abh2Pch, abl2Pcl;
        
    always @( posedge Clks_clk) begin
        if( Clks_extReset) begin
            { dbl2Pcl, dbh2Pch, abh2Pch, abl2Pcl } <= 1'b0;
            
            Pcl2Dbl <= 1'b0;
            Pch2Dbh <= 1'b0;
            Pcl2Abl <= 1'b0;
            Pch2Abh <= 1'b0;
        end
        else if( enT4) begin                // Must latch on T4 !
            dbl2Pcl <= Nanod_dbl2reg & Nanod_pcldbl;
            dbh2Pch <= Nanod_dbh2reg & Nanod_pchdbh;
            abh2Pch <= Nanod_abh2reg & Nanod_pchabh;
            abl2Pcl <= Nanod_abl2reg & Nanod_pclabl;
            
            Pcl2Dbl <= Nanod_reg2dbl & Nanod_pcldbl;
            Pch2Dbh <= Nanod_reg2dbh & Nanod_pchdbh;
            Pcl2Abl <= Nanod_reg2abl & Nanod_pclabl;
            Pch2Abh <= Nanod_reg2abh & Nanod_pchabh;
        end
        
        // Unique IF !!!
        if( enT1 & Nanod_au2Pc)
            PcL <= auReg[15:0];
        else if( enT3) begin
            if( dbl2Pcl)
                PcL <= Dbl;
            else if( abl2Pcl)
                PcL <= Abl;
        end
            
        // Unique IF !!!
        if( enT1 & Nanod_au2Pc)
            PcH <= auReg[31:16];
        else if( enT3) begin
            if( dbh2Pch)
                PcH <= Dbh;
            else if( abh2Pch)
                PcH <= Abh;
        end

        // Unique IF !!!
        if( enT3) begin
            if( Nanod_dbl2Atl)
                Atl <= Dbl;
            else if( Nanod_abl2Atl)
                Atl <= Abl;
        end

        // Unique IF !!!
        if( enT3) begin
            if( Nanod_abh2Ath)
                Ath <= Abh;
            else if( Nanod_dbh2Ath)
                Ath <= Dbh;
        end

    end

    // Movem reg mask priority encoder
    
    wire rmIdle;
    wire [3:0] prHbit;
    reg [15:0] prenLatch;
    
    // Invert reg order for predecrement mode
    assign prenEmpty = (~| prenLatch);  
    pren rmPren( .mask( prenLatch), .hbit (prHbit));

    always @( posedge Clks_clk) begin
        // Cheating: PREN always loaded from DBIN
        // Must be on T1 to branch earlier if reg mask is empty!
        if( enT1 & Nanod_abl2Pren)
            prenLatch <= dbin;
        else if( enT3 & Nanod_updPren) begin
            prenLatch [prHbit] <= 1'b0;
            movemRx <= Irdecod_movemPreDecr ? ~prHbit : prHbit;
        end
    end
    
    // DCR
    wire [15:0] dcrCode;

    wire [3:0] dcrInput = abdIsByte ? { 1'b0, Abd[ 2:0]} : Abd[ 3:0];
    onehotEncoder4 dcrDecoder( .bin( dcrInput), .bitMap( dcrCode));
    
    always @( posedge Clks_clk) begin
        if( Clks_pwrUp)
            dcr4 <= 1'b0;
        else if( enT3 & Nanod_abd2Dcr) begin
            dcrOutput <= dcrCode;
            dcr4 <= Abd[4];
        end
    end
    
    // ALUB
    reg [15:0] alub;
    
    always @( posedge Clks_clk) begin
        if( enT3) begin
            // UNIQUE IF !!
            if( Nanod_dbd2Alub)
                alub <= Dbd;
            else if( Nanod_abd2Alub)
                alub <= Abd;                // abdIsByte affects this !!??
        end
    end
    
    wire alueClkEn = enT3 & Nanod_dbd2Alue;

    // DOB/DBIN/IRC
    
    reg [15:0] dobInput;
    wire dobIdle = (~| Nanod_dobCtrl);
    
    always @* begin
        case (Nanod_dobCtrl)
        NANO_DOB_ADB:       dobInput = Abd;
        NANO_DOB_DBD:       dobInput = Dbd;
        NANO_DOB_ALU:       dobInput = aluOut;
        default:            dobInput = 1'bX;
        endcase
    end

    dataIo dataIo( 
        .Clks_clk,
        .Clks_extReset,         // External sync reset on emulated system
        .Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
        .Clks_enPhi1,
        .Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
        
        .Nanod_permStart,
        .Nanod_waitBusFinish,
        .Nanod_isWrite,
        .Nanod_busByte,
        .Nanod_isRmc,
        .Nanod_noLowByte, .Nanod_noHighByte,
        .Nanod_updTpend, .Nanod_clrTpend,
        .Nanod_tvn2Ftu, .Nanod_const2Ftu,
        .Nanod_ftu2Dbl, .Nanod_ftu2Abl,
        .Nanod_abl2Pren, .Nanod_updPren,
        .Nanod_inl2psw, .Nanod_ftu2Sr, .Nanod_sr2Ftu, .Nanod_ftu2Ccr, .Nanod_pswIToFtu,
        .Nanod_ird2Ftu, .Nanod_ssw2Ftu,
        .Nanod_initST,
        .Nanod_Ir2Ird,
        .Nanod_auClkEn, .Nanod_noSpAlign,
        .Nanod_auCntrl,
        .Nanod_todbin, .Nanod_toIrc,
        .Nanod_dbl2Atl, .Nanod_abl2Atl, .Nanod_atl2Abl, .Nanod_atl2Dbl,
        .Nanod_abh2Ath, .Nanod_dbh2Ath,
        .Nanod_ath2Dbh, .Nanod_ath2Abh,
        .Nanod_db2Aob, .Nanod_ab2Aob, .Nanod_au2Aob,
        .Nanod_aob2Ab, .Nanod_updSsw,
        .Nanod_dobCtrl,
        .Nanod_abh2reg, .Nanod_abl2reg,
        .Nanod_reg2abl, .Nanod_reg2abh,
        .Nanod_dbh2reg, .Nanod_dbl2reg,
        .Nanod_reg2dbl, .Nanod_reg2dbh,
        .Nanod_ssp, .Nanod_pchdbh, .Nanod_pcldbl, .Nanod_pclabl, .Nanod_pchabh,
        .Nanod_rxh2dbh, .Nanod_rxh2abh,
        .Nanod_dbl2rxl, .Nanod_dbh2rxh,
        .Nanod_rxl2db, .Nanod_rxl2ab,
        .Nanod_abl2rxl, .Nanod_abh2rxh,
        .Nanod_dbh2ryh, .Nanod_abh2ryh,
        .Nanod_ryl2db, .Nanod_ryl2ab,
        .Nanod_ryh2dbh, .Nanod_ryh2abh,
        .Nanod_dbl2ryl, .Nanod_abl2ryl,
        .Nanod_rz,
        .Nanod_rxlDbl,
        .Nanod_aluColumn,
        .Nanod_aluDctrl,
        .Nanod_aluActrl,
        .Nanod_aluInit, .Nanod_aluFinish,
        .Nanod_abd2Dcr, .Nanod_dcr2Dbd,
        .Nanod_dbd2Alue, .Nanod_alue2Dbd,
        .Nanod_dbd2Alub, .Nanod_abd2Alub,
        .Nanod_alu2Dbd, .Nanod_alu2Abd,
        .Nanod_au2Db, .Nanod_au2Ab, .Nanod_au2Pc,
        .Nanod_dbin2Abd, .Nanod_dbin2Dbd,
        .Nanod_extDbh, .Nanod_extAbh,
        .Nanod_ablAbd, .Nanod_ablAbh,
        .Nanod_dblDbd, .Nanod_dblDbh,
        .Nanod_abdIsByte,
        
        
        .Irdecod_isPcRel,
        .Irdecod_isTas,
        .Irdecod_implicitSp,
        .Irdecod_toCcr,
        .Irdecod_rxIsDt,
        .Irdecod_ryIsDt,
        .Irdecod_rxIsUsp,
        .Irdecod_rxIsMovem,
        .Irdecod_movemPreDecr,
        .Irdecod_isByte,
        .Irdecod_isMovep,
        .Irdecod_rx,
        .Irdecod_ry,
        .Irdecod_rxIsAreg,
        .Irdecod_ryIsAreg,
        .Irdecod_ftuConst,
        .Irdecod_macroTvn,
        .Irdecod_inhibitCcr,    

        .enT1, .enT2, .enT3, .enT4, 
        .iEdb, .dobIdle, .dobInput, .aob0,
        .Irc, .dbin, .oEdb);

    fx68kAlu alu(
        .clk( Clks_clk), .pwrUp( Clks_pwrUp), .enT1, .enT3, .enT4,
        .ird( Ird),
        .aluColumn( Nanod_aluColumn), .aluAddrCtrl( Nanod_aluActrl),
        .init( Nanod_aluInit), .finish( Nanod_aluFinish), .aluIsByte( Irdecod_isByte),
        .ftu2Ccr( Nanod_ftu2Ccr),
        .alub, .ftu, .alueClkEn, .alue,
        .aluDataCtrl( Nanod_aluDctrl), .iDataBus( Dbd), .iAddrBus(Abd),
        .ze, .aluOut, .ccr);

endmodule


//
// Data bus I/O
// At a separate module because it is a bit complicated and the timing is special.
// Here we do the low/high byte mux and the special case of MOVEP.
//
// Original implementation is rather complex because both the internal and external buses are bidirectional.
// Input is latched async at the EDB register.
// We capture directly from the external data bus to the internal registers (IRC & DBIN) on PHI2, starting the external S7 phase, at a T4 internal period.

module dataIo(
    input Clks_clk,
    input Clks_extReset,         // External sync reset on emulated system
    input Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
    input Clks_enPhi1,
    input Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
    input enT1, enT2, enT3, enT4,

    input Nanod_permStart,
    input Nanod_waitBusFinish,
    input Nanod_isWrite,
    input Nanod_busByte,
    input Nanod_isRmc,
    input Nanod_noLowByte, Nanod_noHighByte,
    input Nanod_updTpend, Nanod_clrTpend,
    input Nanod_tvn2Ftu, Nanod_const2Ftu,
    input Nanod_ftu2Dbl, Nanod_ftu2Abl,
    input Nanod_abl2Pren, Nanod_updPren,
    input Nanod_inl2psw, Nanod_ftu2Sr, Nanod_sr2Ftu, Nanod_ftu2Ccr, Nanod_pswIToFtu,
    input Nanod_ird2Ftu, Nanod_ssw2Ftu,
    input Nanod_initST,
    input Nanod_Ir2Ird,
    input Nanod_auClkEn, Nanod_noSpAlign,
    input [2:0] Nanod_auCntrl,
    input Nanod_todbin, Nanod_toIrc,
    input Nanod_dbl2Atl, Nanod_abl2Atl, Nanod_atl2Abl, Nanod_atl2Dbl,
    input Nanod_abh2Ath, Nanod_dbh2Ath,
    input Nanod_ath2Dbh, Nanod_ath2Abh,
    input Nanod_db2Aob, Nanod_ab2Aob, Nanod_au2Aob,
    input Nanod_aob2Ab, Nanod_updSsw,
    input [1:0] Nanod_dobCtrl,
    input Nanod_abh2reg, Nanod_abl2reg,
    input Nanod_reg2abl, Nanod_reg2abh,
    input Nanod_dbh2reg, Nanod_dbl2reg,
    input Nanod_reg2dbl, Nanod_reg2dbh,
    input Nanod_ssp, Nanod_pchdbh, Nanod_pcldbl, Nanod_pclabl, Nanod_pchabh,
    input Nanod_rxh2dbh, Nanod_rxh2abh,
    input Nanod_dbl2rxl, Nanod_dbh2rxh,
    input Nanod_rxl2db, Nanod_rxl2ab,
    input Nanod_abl2rxl, Nanod_abh2rxh,
    input Nanod_dbh2ryh, Nanod_abh2ryh,
    input Nanod_ryl2db, Nanod_ryl2ab,
    input Nanod_ryh2dbh, Nanod_ryh2abh,
    input Nanod_dbl2ryl, Nanod_abl2ryl,
    input Nanod_rz,
    input Nanod_rxlDbl,
    input [2:0] Nanod_aluColumn,
    input [1:0] Nanod_aluDctrl,
    input Nanod_aluActrl,
    input Nanod_aluInit, Nanod_aluFinish,
    input Nanod_abd2Dcr, Nanod_dcr2Dbd,
    input Nanod_dbd2Alue, Nanod_alue2Dbd,
    input Nanod_dbd2Alub, Nanod_abd2Alub,
    input Nanod_alu2Dbd, Nanod_alu2Abd,
    input Nanod_au2Db, Nanod_au2Ab, Nanod_au2Pc,
    input Nanod_dbin2Abd, Nanod_dbin2Dbd,
    input Nanod_extDbh, Nanod_extAbh,
    input Nanod_ablAbd, Nanod_ablAbh,
    input Nanod_dblDbd, Nanod_dblDbh,
    input Nanod_abdIsByte,


    input        Irdecod_isPcRel,
    input        Irdecod_isTas,
    input        Irdecod_implicitSp,
    input        Irdecod_toCcr,
    input        Irdecod_rxIsDt,
    input        Irdecod_ryIsDt,
    input        Irdecod_rxIsUsp,
    input        Irdecod_rxIsMovem,
    input        Irdecod_movemPreDecr,
    input        Irdecod_isByte,
    input        Irdecod_isMovep,
    input [2:0]  Irdecod_rx,
    input [2:0]  Irdecod_ry,
    input        Irdecod_rxIsAreg,
    input        Irdecod_ryIsAreg,
    input [15:0] Irdecod_ftuConst,
    input [ 5:0] Irdecod_macroTvn,
    input        Irdecod_inhibitCcr,    

    input [15:0] iEdb,
    input aob0,

    input dobIdle,
    input [15:0] dobInput,
    
    output reg [15:0] Irc,    
    output reg [15:0] dbin,
    output wire [15:0] oEdb
    );

    reg [15:0] dob;
    
    // DBIN/IRC
    
    // Timing is different than any other register. We can latch only on the next T4 (bus phase S7).
    // We need to register all control signals correctly because the next ublock will already be started.
    // Can't latch control on T4 because if there are wait states there might be multiple T4 before we latch.
    
    reg xToDbin, xToIrc;
    reg dbinNoLow, dbinNoHigh;
    reg byteMux, isByte_T4;
    
    always @( posedge Clks_clk) begin
    
        // Byte mux control. Can't latch at T1. AOB might be not ready yet.
        // Must latch IRD decode at T1 (or T4). Then combine and latch only at T3.

        // Can't latch at T3, a new IRD might be loaded already at T1.  
        // Ok to latch at T4 if combination latched then at T3
        if( enT4)
            isByte_T4 <= Irdecod_isByte;    // Includes MOVEP from mem, we could OR it here

        if( enT3) begin
            dbinNoHigh <= Nanod_noHighByte;
            dbinNoLow <= Nanod_noLowByte;
            byteMux <= Nanod_busByte & isByte_T4 & ~aob0;
        end
        
        if( enT1) begin
            // If on wait states, we continue latching until next T1
            xToDbin <= 1'b0;
            xToIrc <= 1'b0;         
        end
        else if( enT3) begin
            xToDbin <= Nanod_todbin;
            xToIrc <= Nanod_toIrc;
        end

        // Capture on T4 of the next ucycle
        // If there are wait states, we keep capturing every PHI2 until the next T1
        
        if( xToIrc & Clks_enPhi2)
            Irc <= iEdb;
        if( xToDbin & Clks_enPhi2) begin
            // Original connects both halves of EDB.
            if( ~dbinNoLow)
                dbin[ 7:0] <= byteMux ? iEdb[ 15:8] : iEdb[7:0];
            if( ~dbinNoHigh)
                dbin[ 15:8] <= ~byteMux & dbinNoLow ? iEdb[ 7:0] : iEdb[ 15:8];
        end
    end
    
    // DOB
    reg byteCycle;    
    
    always @( posedge Clks_clk) begin
        // Originaly on T1. Transfer to internal EDB also on T1 (stays enabled upto the next T1). But only on T4 (S3) output enables.
        // It is safe to do on T3, then, but control signals if derived from IRD must be registered.
        // Originally control signals are not registered.
        
        // Wait states don't affect DOB operation that is done at the start of the bus cycle. 

        if( enT4)
            byteCycle <= Nanod_busByte & Irdecod_isByte;        // busIsByte but not MOVEP
        
        // Originally byte low/high interconnect is done at EDB, not at DOB.
        if( enT3 & ~dobIdle) begin
            dob[7:0] <= Nanod_noLowByte ? dobInput[15:8] : dobInput[ 7:0];
            dob[15:8] <= (byteCycle | Nanod_noHighByte) ? dobInput[ 7:0] : dobInput[15:8];
        end
    end
    assign oEdb = dob;

endmodule

// Provides ucode routine entries (A1/A3) for each opcode
// Also checks for illegal opcode and priv violation

// This is one of the slowest part of the processor.
// But no need to optimize or pipeline because the result is not needed until at least 4 cycles.
// IR updated at the least one microinstruction earlier.
// Just need to configure the timing analizer correctly.

module uaddrDecode( 
    input [15:0] opcode,
    output [UADDR_WIDTH-1:0] a1, a2, a3,
    output reg isPriv,
	 output wire isIllegal, isLineA, isLineF,
    output [15:0] lineBmap);
    
    wire [3:0] line = opcode[15:12];
    wire [3:0] eaCol, movEa;

    onehotEncoder4 irLineDecod( line, lineBmap);
    
    assign isLineA = lineBmap[ 'hA];
    assign isLineF = lineBmap[ 'hF];
    
    pla_lined pla_lined( .movEa( movEa), .col( eaCol),
        .opcode( opcode), .lineBmap( lineBmap),
        .palIll( isIllegal), .plaA1( a1), .plaA2( a2), .plaA3( a3) );
    
    // ea decoding   
    assign eaCol = eaDecode( opcode[ 5:0]);
    assign movEa = eaDecode( {opcode[ 8:6], opcode[ 11:9]} );

    // EA decode
    function [3:0] eaDecode;
    input [5:0] eaBits;
    begin
    case( eaBits[ 5:3])
    3'b111:
        case( eaBits[ 2:0])
        3'b000:   eaDecode = 7;            // Absolute short
        3'b001:   eaDecode = 8;            // Absolute long
        3'b010:   eaDecode = 9;            // PC displacement
        3'b011:   eaDecode = 10;           // PC offset
        3'b100:   eaDecode = 11;           // Immediate
        default:  eaDecode = 12;           // Invalid
        endcase
         
    default:   eaDecode = eaBits[5:3];      // Register based EAs
    endcase
    end
    endfunction
    
    
    /*
    Privileged instructions:

    ANDI/EORI/ORI SR
    MOVE to SR
    MOVE to/from USP
    RESET
    RTE
    STOP
    */
    
    always @* begin
        case( lineBmap)
           
        // ori/andi/eori SR      
        'h01:   isPriv = ((opcode & 16'hf5ff) == 16'h007c);
      
        'h10:
            begin
            // No priority !!!
                if( (opcode & 16'hffc0) == 16'h46c0)        // move to sr
                    isPriv = 1'b1;
                
                else if( (opcode & 16'hfff0) == 16'h4e60)   // move usp
                    isPriv = 1'b1;
        
                else if(    opcode == 16'h4e70 ||           // reset
                            opcode == 16'h4e73 ||           // rte
                            opcode == 16'h4e72)             // stop
                    isPriv = 1'b1;
                else
                    isPriv = 1'b0;
            end
         
        default:   isPriv = 1'b0;
        endcase
    end

    
endmodule


// bin to one-hot, 4 bits to 16-bit bitmap
module onehotEncoder4( input [3:0] bin, output reg [15:0] bitMap);
    always @* begin
    case( bin)
        'b0000:   bitMap = 16'h0001;
        'b0001:   bitMap = 16'h0002;
        'b0010:   bitMap = 16'h0004;
        'b0011:   bitMap = 16'h0008;
        'b0100:   bitMap = 16'h0010;
        'b0101:   bitMap = 16'h0020;
        'b0110:   bitMap = 16'h0040;
        'b0111:   bitMap = 16'h0080;
        'b1000:   bitMap = 16'h0100;
        'b1001:   bitMap = 16'h0200;
        'b1010:   bitMap = 16'h0400;
        'b1011:   bitMap = 16'h0800;
        'b1100:   bitMap = 16'h1000;
        'b1101:   bitMap = 16'h2000;
        'b1110:   bitMap = 16'h4000;
        'b1111:   bitMap = 16'h8000;
    endcase
    end
endmodule



// priority encoder
// used by MOVEM regmask
// this might benefit from device specific features
// MOVEM doesn't need speed, will read the result 2 CPU cycles after each update.
module pren( mask, hbit);
   parameter size = 16;
   parameter outbits = 4;

   input [size-1:0] mask;
   output reg [outbits-1:0] hbit;
   // output reg idle;
   integer i;
   always @( mask) begin
      hbit = 0;
      // idle = 1;
      for( i = size-1; i >= 0; i = i - 1) begin
          if( mask[ i]) begin
             hbit = i;
             // idle = 0;
         end
      end
   end

endmodule



// Microcode sequencer

module sequencer( 
    input Clks_clk,
    input Clks_extReset,         // External sync reset on emulated system
    input Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
    input Clks_enPhi1,
    input Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2
    input enT3,
    input [UROM_WIDTH-1:0] microLatch,
    input A0Err, BerrA, busAddrErr, Spuria, Avia,
    input Tpend, intPend, isIllegal, isPriv, excRst, isLineA, isLineF,
    input [15:0] psw,
    input prenEmpty, au05z, dcr4, ze, i11,
    input [1:0] alue01,
    input [15:0] Ird,
    input [UADDR_WIDTH-1:0] a1, a2, a3,
    output reg [3:0] tvn,
    output reg [UADDR_WIDTH-1:0] nma);
    
    reg [UADDR_WIDTH-1:0] uNma;
    reg [UADDR_WIDTH-1:0] grp1Nma;    
    reg [1:0] c0c1;
    reg a0Rst;
    wire A0Sel;
    wire inGrp0Exc;
    
    // assign nma = Clks_extReset ? RSTP0_NMA : (A0Err ? BSER1_NMA : uNma);
    // assign nma = A0Err ? (a0Rst ? RSTP0_NMA : BSER1_NMA) : uNma;
    
    // word type I: 16 15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00
    // NMA :        .. .. 09 08 01 00 05 04 03 02 07 06 .. .. .. .. ..
    
    wire [UADDR_WIDTH-1:0] dbNma = { microLatch[ 14:13], microLatch[ 6:5], microLatch[ 10:7], microLatch[ 12:11]};

    // Group 0 exception.
    // Separated block from regular NMA. Otherwise simulation might depend on order of assigments.
    always @* begin
        if( A0Err) begin
            if( a0Rst)                  // Reset
                nma = RSTP0_NMA;
            else if( inGrp0Exc)         // Double fault
                nma = HALT1_NMA;
            else                        // Bus or address error
                nma = BSER1_NMA;
        end
        else
            nma = uNma;
    end

    always @* begin
        // Format II (conditional) or I (direct branch)
        if( microLatch[1])
            uNma = { microLatch[ 14:13], c0c1, microLatch[ 10:7], microLatch[ 12:11]};      
        else
            case( microLatch[ 3:2])
            0:   uNma = dbNma;   // DB
            1:   uNma = A0Sel ? grp1Nma : a1;
            2:   uNma = a2;
            3:   uNma = a3;
            endcase         
    end

    // Format II, conditional, NMA decoding
    wire [1:0] enl = { Ird[6], prenEmpty};      // Updated on T3
    
    wire [1:0] ms0 = { Ird[8], alue01[0]};
    wire [3:0] m01 = { au05z, Ird[8], alue01};
    wire [1:0] nz1 = { psw[ NF], psw[ ZF]};
    wire [1:0] nv  = { psw[ NF], psw[ VF]};
    
    reg ccTest;
    wire [4:0] cbc = microLatch[ 6:2];          // CBC bits
    
    always @* begin
        case( cbc)
        'h0:    c0c1 = {i11, i11};                      // W/L offset EA, from IRC

        'h1:    c0c1 = (au05z) ? 2'b01 : 2'b11;         // Updated on T3
        'h11:   c0c1 = (au05z) ? 2'b00 : 2'b11;

        'h02:   c0c1 = { 1'b0, ~psw[ CF]};              // C used in DIV
        'h12:   c0c1 = { 1'b1, ~psw[ CF]};

        'h03:   c0c1 = {psw[ ZF], psw[ ZF]};            // Z used in DIVU
        
        'h04:                                           // nz1, used in DIVS
            case( nz1)
               'b00:         c0c1 = 2'b10;
               'b10:         c0c1 = 2'b01;
               'b01,'b11:    c0c1 = 2'b11;
            endcase     

        'h05:   c0c1 = {psw[ NF], 1'b1};                // N used in CHK and DIV
        'h15:   c0c1 = {1'b1, psw[ NF]};
        
        // nz2, used in DIVS (same combination as nz1)
        'h06:   c0c1 = { ~nz1[1] & ~nz1[0], 1'b1};
        
        'h07:                                           // ms0 used in MUL
        case( ms0)
         'b10, 'b00: c0c1 = 2'b11;
         'b01: c0c1 = 2'b01;
         'b11: c0c1 = 2'b10;
        endcase     
        
        'h08:                                           // m01 used in MUL
        case( m01)
        'b0000,'b0001,'b0100,'b0111:  c0c1 = 2'b11;
        'b0010,'b0011,'b0101:         c0c1 = 2'b01;
        'b0110:                       c0c1 = 2'b10;
        default:                      c0c1 = 2'b00;
        endcase

        // Conditional      
        'h09:   c0c1 = (ccTest) ? 2'b11 : 2'b01;
        'h19:   c0c1 = (ccTest) ? 2'b11 : 2'b10;
        
        // DCR bit 4 (high or low word)
        'h0c:   c0c1 = dcr4 ? 2'b01: 2'b11;
        'h1c:   c0c1 = dcr4 ? 2'b10: 2'b11;     
        
        // DBcc done
        'h0a:   c0c1 = ze ? 2'b11 : 2'b00;
        
        // nv, used in CHK
        'h0b:   c0c1 = (nv == 2'b00) ? 2'b00 : 2'b11;
        
        // V, used in trapv
        'h0d:   c0c1 = { ~psw[ VF], ~psw[VF]};      
        
        // enl, combination of pren idle and word/long on IRD
        'h0e,'h1e:
            case( enl)
            2'b00:  c0c1 = 'b10;
            2'b10:  c0c1 = 'b11;
            // 'hx1 result 00/01 depending on condition 0e/1e
            2'b01,2'b11:
                    c0c1 = { 1'b0, microLatch[ 6]};
            endcase
            
        default:                c0c1 = 1'bX;
        endcase
    end
    
    // CCR conditional
    always @* begin
        case( Ird[ 11:8])       
        'h0: ccTest = 1'b1;                     // T
        'h1: ccTest = 1'b0;                     // F
        'h2: ccTest = ~psw[ CF] & ~psw[ ZF];    // HI
        'h3: ccTest = psw[ CF] | psw[ZF];       // LS
        'h4: ccTest = ~psw[ CF];                // CC (HS)
        'h5: ccTest = psw[ CF];                 // CS (LO)
        'h6: ccTest = ~psw[ ZF];                // NE
        'h7: ccTest = psw[ ZF];                 // EQ
        'h8: ccTest = ~psw[ VF];                // VC
        'h9: ccTest = psw[ VF];                 // VS
        'ha: ccTest = ~psw[ NF];                // PL
        'hb: ccTest = psw[ NF];                 // MI
        'hc: ccTest = (psw[ NF] & psw[ VF]) | (~psw[ NF] & ~psw[ VF]);              // GE
        'hd: ccTest = (psw[ NF] & ~psw[ VF]) | (~psw[ NF] & psw[ VF]);              // LT
        'he: ccTest = (psw[ NF] & psw[ VF] & ~psw[ ZF]) |
                 (~psw[ NF] & ~psw[ VF] & ~psw[ ZF]);                               // GT
        'hf: ccTest = psw[ ZF] | (psw[ NF] & ~psw[VF]) | (~psw[ NF] & psw[VF]);     // LE
        endcase
    end
    
    // Exception logic
    reg rTrace, rInterrupt;
    reg rIllegal, rPriv, rLineA, rLineF;
    reg rExcRst, rExcAdrErr, rExcBusErr;
    reg rSpurious, rAutovec;
    wire grp1LatchEn, grp0LatchEn;
            
    // Originally control signals latched on T4. Then exception latches updated on T3
    assign grp1LatchEn = microLatch[0] & (microLatch[1] | !microLatch[4]);
    assign grp0LatchEn = microLatch[4] & !microLatch[1];
    
    assign inGrp0Exc = rExcRst | rExcBusErr | rExcAdrErr;
    
    always @( posedge Clks_clk) begin
        if( grp0LatchEn & enT3) begin
            rExcRst <= excRst;
            rExcBusErr <= BerrA;
            rExcAdrErr <= busAddrErr;
            rSpurious <= Spuria;
            rAutovec <= Avia;
        end
        
        // Update group 1 exception latches
        // Inputs from IR decoder updated on T1 as soon as IR loaded
        // Trace pending updated on T3 at the start of the instruction
        // Interrupt pending on T2
        if( grp1LatchEn & enT3) begin
            rTrace <= Tpend;
            rInterrupt <= intPend;
            rIllegal <= isIllegal & ~isLineA & ~isLineF;
            rLineA <= isLineA;
            rLineF <= isLineF;
            rPriv <= isPriv & !psw[ SF];
        end
    end

    // exception priority
    always @* begin
        grp1Nma = TRAC1_NMA;
        if( rExcRst)
            tvn = 1'b0;                           // Might need to change that to signal in exception
        else if( rExcBusErr | rExcAdrErr)
            tvn = { 1'b1, rExcAdrErr};
            
        // Seudo group 0 exceptions. Just for updating TVN
        else if( rSpurious | rAutovec)
            tvn = rSpurious ? TVN_SPURIOUS : TVN_AUTOVEC;
        
        else if( rTrace)
            tvn = 9;
        else if( rInterrupt) begin
            tvn = TVN_INTERRUPT;
            grp1Nma = ITLX1_NMA;
        end
        else begin
            case( 1'b1)                 // Can't happen more than one of these
            rIllegal:           tvn = 4;
            rPriv:              tvn = 8;
            rLineA:             tvn = 10;
            rLineF:             tvn = 11;
            default:            tvn = 1;        // Signal no group 0/1 exception
            endcase
        end
    end
    
    assign A0Sel = rIllegal | rLineF | rLineA | rPriv | rTrace | rInterrupt;
    
    always @( posedge Clks_clk) begin
        if( Clks_extReset)
            a0Rst <= 1'b1;
        else if( enT3)
            a0Rst <= 1'b0;
    end
    
endmodule



//
// DMA/BUS Arbitration
//

module busArbiter(
        input Clks_clk,
        input Clks_extReset,         // External sync reset on emulated system
        input Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
        input Clks_enPhi1,
        input Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2

        input BRi, BgackI, Halti, bgBlock,
        output busAvail,
        output reg BGn);
        
    localparam [2:0] DRESET = 3'd0, DIDLE=3'd1, D1=3'd2, D_BR=3'd3, D_BA=3'd4, D_BRA=3'd5, D3=3'd6, D2=3'd7;
    reg [2:0] dmaPhase, next;

    always @* begin
        case(dmaPhase)
        DRESET: next = DIDLE;
        DIDLE:  begin
                if( bgBlock)
                    next = DIDLE;
                else if( ~BgackI)
                    next = D_BA;
                else if( ~BRi)
                    next = D1;
                else
                    next = DIDLE;
                end

        D_BA:   begin                           // Loop while only BGACK asserted, BG negated here
                if( ~BRi & !bgBlock)
                    next = D3;
                else if( ~BgackI & !bgBlock)
                    next = D_BA;
                else
                    next = DIDLE;
                end
                
        D1:     next = D_BR;                            // Loop while only BR asserted
        D_BR:   next = ~BRi & BgackI ? D_BR : D_BA;     // No direct path to IDLE !
        
        D3:     next = D_BRA;
        D_BRA:  begin                       // Loop while both BR and BGACK asserted
                case( {BgackI, BRi} )
                2'b11:  next = DIDLE;       // Both deasserted
                2'b10:  next = D_BR;        // BR asserted only
                2'b01:  next = D2;          // BGACK asserted only
                2'b00:  next = D_BRA;       // Stay here while both asserted
                endcase
                end
                
        // Might loop here if both deasserted, should normally don't arrive here anyway?
        // D2:      next = (BgackI & BRi) | bgBlock ? D2: D_BA;

        D2:     next = D_BA;
        
        default:    next = DIDLE;           // Should not reach here normally       
        endcase
    end
        
    reg granting;
    always @* begin
        case( next)
        D1, D3, D_BR, D_BRA:    granting = 1'b1;
        default:                granting = 1'b0;
        endcase
    end
    
    reg rGranted;
    assign busAvail = Halti & BRi & BgackI & ~rGranted;
        
    always @( posedge Clks_clk) begin
        if( Clks_extReset) begin
            dmaPhase <= DRESET;
            rGranted <= 1'b0;
        end
        else if( Clks_enPhi2) begin
            dmaPhase <= next;
            // Internal signal changed on PHI2
            rGranted <= granting;
        end

        // External Output changed on PHI1
        if( Clks_extReset)
            BGn <= 1'b1;
        else if( Clks_enPhi1)
            BGn <= ~rGranted;
        
    end
            
endmodule



module busControl( 
        //input s_clks Clks, 
        input Clks_clk,
        input Clks_extReset,         // External sync reset on emulated system
        input Clks_pwrUp,            // Asserted together with reset on emulated system coldstart
        input Clks_enPhi1,
        input Clks_enPhi2,           // Clock enables. Next cycle is PHI1 or PHI2

        input enT1, 
        input enT4,
        input permStart, permStop, iStop,
        input aob0,
        input isWrite, isByte, isRmc,
        input busAvail,
        output bgBlock,
        output busAddrErr,
        output waitBusCycle,
        output busStarting,         // Asserted during S0
        output reg addrOe,        // Asserted from S1 to the end, whole bus cycle except S0
        output bciWrite,            // Used for SSW on bus/addr error
        
        input rDtack, BeDebounced, Vpai,
        output ASn, output LDSn, output UDSn, eRWn);

    reg rAS, rLDS, rUDS, rRWn;
    assign ASn = rAS;
    assign LDSn = rLDS;
    assign UDSn = rUDS;
    assign eRWn = rRWn;

    reg dataOe;
        
    reg bcPend;
    reg isWriteReg, bciByte, isRmcReg, wendReg;
    assign bciWrite = isWriteReg;
    reg addrOeDelay;
    reg isByteT4;

    wire canStart, busEnd;
    wire bcComplete, bcReset;
    
    wire isRcmReset = bcComplete & bcReset & isRmcReg;
    
    assign busAddrErr = aob0 & ~bciByte;
    
    // Bus retry not really supported.
    // It's BERR and HALT and not address error, and not read-modify cycle.
    wire busRetry = ~busAddrErr & 1'b0;
    localparam [2:0] SRESET =3'd0, SIDLE=3'd1, S0=3'd2, S2=3'd3, S4=3'd4, S6=3'd5, SRMC_RES=3'd6;
    reg [2:0] busPhase, next;

    always @( posedge Clks_clk) begin
        if( Clks_extReset)
            busPhase <= SRESET;
        else if( Clks_enPhi1)
            busPhase <= next;
    end
    
    always @* begin
        case( busPhase)
        SRESET:     next = SIDLE;
        SRMC_RES:   next = SIDLE;           // Single cycle special state when read phase of RMC reset
        S0:         next = S2;
        S2:         next = S4;
        S4:         next = busEnd ? S6 : S4;
        S6:         next = isRcmReset ? SRMC_RES : (canStart ? S0 : SIDLE);
        SIDLE:      next = canStart ? S0 : SIDLE;
        default:    next = SIDLE;
        endcase
    end 
    
    // Idle phase of RMC bus cycle. Might be better to just add a new state
    wire rmcIdle = (busPhase == SIDLE) & ~ASn & isRmcReg;
        
    assign canStart = (busAvail | rmcIdle) & (bcPend | permStart) & !busRetry & !bcReset;
        
    wire busEnding = (next == SIDLE) | (next == S0);
    
    assign busStarting = (busPhase == S0);
        
    // term signal (DTACK, BERR, VPA, adress error)
    assign busEnd = ~rDtack | iStop;
                
    // bcComplete asserted on raising edge of S6 (together with SNC).
    assign bcComplete = (busPhase == S6);
    
    // Clear bus info latch on completion (regular or aborted) and no bus retry (and not PHI1).
    // bciClear asserted half clock later on PHI2, and bci latches cleared async concurrently
    wire bciClear = bcComplete & ~busRetry;
    
    // Reset on reset or (berr & berrDelay & (not halt or rmc) & not 6800 & in bus cycle) (and not PHI1)
    assign bcReset = Clks_extReset | (addrOeDelay & BeDebounced & Vpai);
        
    // Enable uclock only on S6 (S8 on Bus Error) or not bciPermStop
    assign waitBusCycle = wendReg & !bcComplete;
    
    // Block Bus Grant when starting new bus cycle. But No need if AS already asserted (read phase of RMC)
    // Except that when that RMC phase aborted on bus error, it's asserted one cycle later!
    assign bgBlock = ((busPhase == S0) & ASn) | (busPhase == SRMC_RES);
    
    always @( posedge Clks_clk) begin
        if( Clks_extReset) begin
            addrOe <= 1'b0;
        end
        else if( Clks_enPhi2 & ( busPhase == S0))           // From S1, whole bus cycle except S0
                addrOe <= 1'b1;
        else if( Clks_enPhi1 & (busPhase == SRMC_RES))
            addrOe <= 1'b0;
        else if( Clks_enPhi1 & ~isRmcReg & busEnding)
            addrOe <= 1'b0;
            
        if( Clks_enPhi1)
            addrOeDelay <= addrOe;
        
        if( Clks_extReset) begin
            rAS <= 1'b1;
            rUDS <= 1'b1;
            rLDS <= 1'b1;
            rRWn <= 1'b1;
            dataOe <= 1'b0;
        end
        else begin

            if( Clks_enPhi2 & isWriteReg & (busPhase == S2))
                dataOe <= 1'b1;
            else if( Clks_enPhi1 & (busEnding | (busPhase == SIDLE)) )
                dataOe <= 1'b0;
                        
            if( Clks_enPhi1 & busEnding)
                rRWn <= 1'b1;
            else if( Clks_enPhi1 & isWriteReg) begin
                // Unlike LDS/UDS Asserted even in address error
                if( (busPhase == S0) & isWriteReg)
                    rRWn <= 1'b0;
            end

            // AS. Actually follows addrOe half cycle later!
            if( Clks_enPhi1 & (busPhase == S0))
                rAS <= 1'b0;
            else if( Clks_enPhi2 & (busPhase == SRMC_RES))      // Bus error on read phase of RMC. Deasserted one cycle later
                rAS <= 1'b1;            
            else if( Clks_enPhi2 & bcComplete & ~SRMC_RES)
                if( ~isRmcReg)                                  // Keep AS asserted on the IDLE phase of RMC
                    rAS <= 1'b1;
            
            if( Clks_enPhi1 & (busPhase == S0)) begin
                if( ~isWriteReg & !busAddrErr) begin
                    rUDS <= ~(~bciByte | ~aob0);
                    rLDS <= ~(~bciByte | aob0);
                end
            end
            else if( Clks_enPhi1 & isWriteReg & (busPhase == S2) & !busAddrErr) begin
                    rUDS <= ~(~bciByte | ~aob0);
                    rLDS <= ~(~bciByte | aob0);
            end     
            else if( Clks_enPhi2 & bcComplete) begin
                rUDS <= 1'b1;
                rLDS <= 1'b1;
            end
            
        end
        
    end
    
    // Bus cycle info latch. Needed because uinstr might change if the bus is busy and we must wait.
    // Note that urom advances even on wait states. It waits *after* updating urom and nanorom latches.
    // Even without wait states, ublocks of type ir (init reading) will not wait for bus completion.
    // Originally latched on (permStart AND T1).
    
    // Bus cycle info latch: isRead, isByte, read-modify-cycle, and permStart (bus cycle pending). Some previously latched on T4?
    // permStop also latched, but unconditionally on T1
    
    // Might make more sense to register this outside this module
    always @( posedge Clks_clk) begin
        if( enT4) begin
            isByteT4 <= isByte;
        end
    end
    
    // Bus Cycle Info Latch
    always @( posedge Clks_clk) begin
        if( Clks_pwrUp) begin
            bcPend <= 1'b0;
            wendReg <= 1'b0;    
            isWriteReg <= 1'b0;
            bciByte <= 1'b0;
            isRmcReg <= 1'b0;       
        end
        
        else if( Clks_enPhi2 & (bciClear | bcReset)) begin
            bcPend <= 1'b0;
            wendReg <= 1'b0;
        end
        else begin
            if( enT1 & permStart) begin
                isWriteReg <= isWrite;
                bciByte <= isByteT4;
                isRmcReg <= isRmc & ~isWrite;   // We need special case the end of the read phase only.
                bcPend <= 1'b1;
            end
            if( enT1)
                wendReg <= permStop;
        end
    end
            
endmodule



//
// microrom and nanorom instantiation
//
// There is bit of wasting of resources here. An extra registering pipeline happens that is not needed.
// This is just for the purpose of helping inferring block RAM using pure generic code. Inferring RAM is important for performance.
// Might be more efficient to use vendor specific features such as clock enable.
//

module uRom( input clk, input [UADDR_WIDTH-1:0] microAddr, output reg [UROM_WIDTH-1:0] microOutput);
    reg [UROM_WIDTH-1:0] uRam[0:UROM_DEPTH-1];     
    initial begin
        $readmemb("microrom.mem", uRam);
    end
    
    always @( posedge clk) 
        microOutput <= uRam[ microAddr];
endmodule


module nanoRom( input clk, input [NADDR_WIDTH-1:0] nanoAddr, output reg [NANO_WIDTH-1:0] nanoOutput);
    reg [NANO_WIDTH-1:0] nRam[0:NANO_DEPTH-1];     
    initial begin
        $readmemb("nanorom.mem", nRam);
    end
    
    always @( posedge clk) 
        nanoOutput <= nRam[ nanoAddr];
endmodule


// Translate uaddr to nanoaddr
module microToNanoAddr(
    input [UADDR_WIDTH-1:0] uAddr,
    output [NADDR_WIDTH-1:0] orgAddr);

    wire [UADDR_WIDTH-1:2] baseAddr = uAddr[UADDR_WIDTH-1:2];
    reg [NADDR_WIDTH-1:2] orgBase;
    assign orgAddr = { orgBase, uAddr[1:0]};

    always @( baseAddr)
    begin
        // nano ROM (136 addresses)
        case( baseAddr)

'h00: orgBase = 7'h0 ;
'h01: orgBase = 7'h1 ;
'h02: orgBase = 7'h2 ;
'h03: orgBase = 7'h2 ;
'h08: orgBase = 7'h3 ;
'h09: orgBase = 7'h4 ;
'h0A: orgBase = 7'h5 ;
'h0B: orgBase = 7'h5 ;
'h10: orgBase = 7'h6 ;
'h11: orgBase = 7'h7 ;
'h12: orgBase = 7'h8 ;
'h13: orgBase = 7'h8 ;
'h18: orgBase = 7'h9 ;
'h19: orgBase = 7'hA ;
'h1A: orgBase = 7'hB ;
'h1B: orgBase = 7'hB ;
'h20: orgBase = 7'hC ;
'h21: orgBase = 7'hD ;
'h22: orgBase = 7'hE ;
'h23: orgBase = 7'hD ;
'h28: orgBase = 7'hF ;
'h29: orgBase = 7'h10 ;
'h2A: orgBase = 7'h11 ;
'h2B: orgBase = 7'h10 ;
'h30: orgBase = 7'h12 ;
'h31: orgBase = 7'h13 ;
'h32: orgBase = 7'h14 ;
'h33: orgBase = 7'h14 ;
'h38: orgBase = 7'h15 ;
'h39: orgBase = 7'h16 ;
'h3A: orgBase = 7'h17 ;
'h3B: orgBase = 7'h17 ;
'h40: orgBase = 7'h18 ;
'h41: orgBase = 7'h18 ;
'h42: orgBase = 7'h18 ;
'h43: orgBase = 7'h18 ;
'h44: orgBase = 7'h19 ;
'h45: orgBase = 7'h19 ;
'h46: orgBase = 7'h19 ;
'h47: orgBase = 7'h19 ;
'h48: orgBase = 7'h1A ;
'h49: orgBase = 7'h1A ;
'h4A: orgBase = 7'h1A ;
'h4B: orgBase = 7'h1A ;
'h4C: orgBase = 7'h1B ;
'h4D: orgBase = 7'h1B ;
'h4E: orgBase = 7'h1B ;
'h4F: orgBase = 7'h1B ;
'h54: orgBase = 7'h1C ;
'h55: orgBase = 7'h1D ;
'h56: orgBase = 7'h1E ;
'h57: orgBase = 7'h1F ;
'h5C: orgBase = 7'h20 ;
'h5D: orgBase = 7'h21 ;
'h5E: orgBase = 7'h22 ;
'h5F: orgBase = 7'h23 ;
'h70: orgBase = 7'h24 ;
'h71: orgBase = 7'h24 ;
'h72: orgBase = 7'h24 ;
'h73: orgBase = 7'h24 ;
'h74: orgBase = 7'h24 ;
'h75: orgBase = 7'h24 ;
'h76: orgBase = 7'h24 ;
'h77: orgBase = 7'h24 ;
'h78: orgBase = 7'h25 ;
'h79: orgBase = 7'h25 ;
'h7A: orgBase = 7'h25 ;
'h7B: orgBase = 7'h25 ;
'h7C: orgBase = 7'h25 ;
'h7D: orgBase = 7'h25 ;
'h7E: orgBase = 7'h25 ;
'h7F: orgBase = 7'h25 ;
'h84: orgBase = 7'h26 ;
'h85: orgBase = 7'h27 ;
'h86: orgBase = 7'h28 ;
'h87: orgBase = 7'h29 ;
'h8C: orgBase = 7'h2A ;
'h8D: orgBase = 7'h2B ;
'h8E: orgBase = 7'h2C ;
'h8F: orgBase = 7'h2D ;
'h94: orgBase = 7'h2E ;
'h95: orgBase = 7'h2F ;
'h96: orgBase = 7'h30 ;
'h97: orgBase = 7'h31 ;
'h9C: orgBase = 7'h32 ;
'h9D: orgBase = 7'h33 ;
'h9E: orgBase = 7'h34 ;
'h9F: orgBase = 7'h35 ;
'hA4: orgBase = 7'h36 ;
'hA5: orgBase = 7'h36 ;
'hA6: orgBase = 7'h37 ;
'hA7: orgBase = 7'h37 ;
'hAC: orgBase = 7'h38 ;
'hAD: orgBase = 7'h38 ;
'hAE: orgBase = 7'h39 ;
'hAF: orgBase = 7'h39 ;
'hB4: orgBase = 7'h3A ;
'hB5: orgBase = 7'h3A ;
'hB6: orgBase = 7'h3B ;
'hB7: orgBase = 7'h3B ;
'hBC: orgBase = 7'h3C ;
'hBD: orgBase = 7'h3C ;
'hBE: orgBase = 7'h3D ;
'hBF: orgBase = 7'h3D ;
'hC0: orgBase = 7'h3E ;
'hC1: orgBase = 7'h3F ;
'hC2: orgBase = 7'h40 ;
'hC3: orgBase = 7'h41 ;
'hC8: orgBase = 7'h42 ;
'hC9: orgBase = 7'h43 ;
'hCA: orgBase = 7'h44 ;
'hCB: orgBase = 7'h45 ;
'hD0: orgBase = 7'h46 ;
'hD1: orgBase = 7'h47 ;
'hD2: orgBase = 7'h48 ;
'hD3: orgBase = 7'h49 ;
'hD8: orgBase = 7'h4A ;
'hD9: orgBase = 7'h4B ;
'hDA: orgBase = 7'h4C ;
'hDB: orgBase = 7'h4D ;
'hE0: orgBase = 7'h4E ;
'hE1: orgBase = 7'h4E ;
'hE2: orgBase = 7'h4F ;
'hE3: orgBase = 7'h4F ;
'hE8: orgBase = 7'h50 ;
'hE9: orgBase = 7'h50 ;
'hEA: orgBase = 7'h51 ;
'hEB: orgBase = 7'h51 ;
'hF0: orgBase = 7'h52 ;
'hF1: orgBase = 7'h52 ;
'hF2: orgBase = 7'h52 ;
'hF3: orgBase = 7'h52 ;
'hF8: orgBase = 7'h53 ;
'hF9: orgBase = 7'h53 ;
'hFA: orgBase = 7'h53 ;
'hFB: orgBase = 7'h53 ;

            default:
                orgBase = 1'bX;
        endcase
    end

endmodule
