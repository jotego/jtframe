# Game clocks

Games are expected to operate on a 48MHz clock using clock enable signals. There is an optional 6MHz that can be enabled with the macro **JTFRAME_CLK6**. This clock goes in the game module through a _clk6_ port which is only connected to when that macro is defined. _jtbtiger_ is an example of game using this feature.

 clock input | Macro Needed
-------------|--------------
clk          | 48MHz unless JTFRAME_SDRAM96 is defined, then 96MHz
clk96        | JTFRAME_CLK96
clk48        | JTFRAME_CLK48
clk24        | JTFRAME_CLK24
clk6         | JTFRAME_CLK6

Note that although clk6 and clk24 are obtained without affecting the main clock input, if **JTFRAME_SDRAM96** is defined, the main clock input moves up from 48MHz to 96MHz. The 48MHz clock can the be obtained from clk48 if **JTFRAME_CLK48** is defined too. This implies that the SDRAM will be clocked at 96MHz instead of 48MHz. The constraints in the SDC files have to match this clock variation.

If STA was to be run on these pins, the SDRAM clock would have to be assigned the correct PLL output in the SDC file but this is hard to do because the TCL language subset used by Quartus seems to lack control flow statements. So we are required to do another text edit hack on the fly, which is not nice. Apart from changing the PLL output, when using 96MHz clock the input data should have a multicycle path constraint as it takes an extra clock cycle for the data to be ready. If you just change the PLL clock then you'll find plenty of timing problems unless you define the multicycle path constraint.

This is the code needed:

```
create_generated_clock -name SDRAM_CLK -source \
    [get_pins {emu|pll|pll_inst|altera_pll_i|general[5].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    -divide_by 1 \
    [get_ports SDRAM_CLK]

set_multicycle_path -from [get_ports {SDRAM_DQ[*]}] -to [get_clocks {emu|pll|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -setup -end 2

set_multicycle_path -from [get_ports {SDRAM_DQ[*]}] -to [get_clocks {emu|pll|pll_inst|altera_pll_i|general[4].gpll~PLL_OUTPUT_COUNTER|divclk}] -hold -end 2
```

This only applies to MiSTer. For MiST the approach is different and there are two different PLL modules which produce the SDRAM clock at the same pin. So a single `create_generated_clock` applies to both. Due to different SDRAM shifts used, the multicycle path constraint does not seem needed in MiST.

The script **jtcore** handles this process transparently.

By default unless **JTFRAME_MR_FASTIO** is already defined, **JTFRAME_CLK96** will define it to 1. This enables fast ROM download in MiSTer using 16-bit mode in _hps_io_.

# Internal JTFRAME clocks

The clocks passed to the target subsystem (jtframe_mist, jtframe_mister or jtframe_neptuno) are three:

clock     |  Use                    | Frequency
----------|-------------------------|--------------------
clk_sys   | Video & general purpose | same as game clock **clk**
clk_rom   | SDRAM access            | same as clk_sys or higher
clk_pico  | picoBlaze clock         | 48MHz

clk_rom is controlled by the macros **JTFRAME_SDRAM96**
clk_sys is normally 48MHz, even if clk_rom is 96MHz. It can be set to 96MHz with **JTFRAME_CLK96**.

Games can move these frequencies by replacing the PLL (using the **JTFRAME_PLL** macro) but the changes should be within ±10% of the expected values. So far, only System16 moves these frequencies from 48MHz to ~50MHz
