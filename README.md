JTFRAME by Jose Tejada (@topapate)
==================================

JTFRAME is a framework for FPGA computing on the MiST and MiSTer platform. JTFRAME is also a collection of useful verilog modules, simulation models and utilities to develop retro hardware on FPGA.

This is a work in progress. The first version will be considered ready once the 1942, 1943, Ghosts'n Goblins and Popeye cores all use JTFRAME common files.

You can show your appreciation through
    * Patreon: https://patreon.com/topapate
    * Paypal: https://paypal.me/topapate

CPUs
====

Some CPUs are included in JTFRAME. Some of them can be found in other repositories in Github but the versions in JTFRAME include clock enable inputs and other improvements.

Simulation of 74-series based schematics
========================================

Many arcade games and 80's computers use 74-series devices to do discrete logic. There are some files in JTFRAME that help analyze these systems using the following flow:

1. Draw the schematics in KiCAD using the libraries in the kicad folder
2. Generate a netlist in standard KiCAD format
3. Use the pcb2ver utility in the cc folder to convert the output from KiCAD to a verilog file
4. Prepare a module wrapper for the new verilog file and include the verilog file in the wrapper via an include command
5. Simulate the file with a regular verilog simulator.

There is a verilog library of 74-series gates in the hdl folder: hdl/jt74.v. The ones that include // ref and // pin comments can be used for KiCAD sims. It is very easy to add support for more cells. Feel free to submit pull merges to Github.

It makes sense to simulate delays in 74-series gates as this is important in some designs. Even if some cells do not include delays, later versions of jt74.v may include delays for all cells. It is not recommended to set up your simulations with Verilator because Verilator does not support delays and other modelling constructs. The jt74 library is not meant for synthesis, only simulation.

Cabinet inputs during simulation
================================
You can use a hex file with inputs for simulation. Enable this with the macro
SIM_INPUTS. The file must be called sim_inputs.hex. Each line has a hexadecimal
number with inputs coded. Active high only:

bit         meaning
0           coin 1
1           coin 2
2           1P start
3           2P start
4
5
6
7
8           Button 1
9           Button 2

OSD colours
===========
The macro JTFRAME_OSDCOLOR should be defined with a 6-bit value encoding an RGB tone. This is used for
the OSD background. The meanins are:

Value | Meaning                 | Colour
======|=========================|========
6'h3f | Mature core             | Gray
6'h1e | Almost done             | Green
6'h3c | Playable with problems  | Yellow
6'h35 | Very early core         | Red

SDRAM Controller
================

**jtframe_sdram** is a generic SDRAM controller that runs upto 48MHz because it is designed for CL=2. It mainly serves for reading ROMs from the SDRAM but it has some support for writting (apart from the initial ROM download process).

This module may result in timing errors in MiSTer because sometimes the compiler does not assign the input flip flops from SDRAM_DQ at the pads. In order to avoid this, you can define the macro **JTFRAME_SDRAM_REPACK**. This will add one extra stage of data latching, which seems to allow the fitter to use the pad flip flops. This does delay data availability by one clock cycle. Some cores in MiSTer do synthesize with pad FF without the need of this option. Use it if you find setup timing violation about the SDRAM_DQ pins.

SDRAM is treated in top level modules as a read-only memory (except for the download process). If the game core needs to write to the SDRAM the **JTFRAME_WRITEBACK** macro must be defined.

SDRAM Simulation
================

A model for SDRAM mt48lc16m16a2 is included in JTFRAME. The model will load the contents of the file **sdram.hex** if available at the beginning of simulation.

The current contents of the SDRAM can be dumped at the beginning of each frame (falling edge of vertical blank) if **JTFRAME_SAVESDRAM** is defined. Because this is quite an overhead, it is possible to restrict it to dump only a certain **DUMP_START** frame count has been reached. All frames will be dumped after it. The macro **DUMP_START** is the same one used for setting the start of signal dump to the __VCD__ file.

Modules with simulation files added automatically
=================================================
Define and export the following environgment variables to have these
modules added to your simulation when using sim.sh

YM2203
YM2149
YM2151
MSM5205
M6801
M6809
I8051

# JTCORE

jtcore is the script used to compile the cores.

## JTAG Programming

jtcore can also program the FPGA (MiST or MiSTer) with the ```-p``` option. In order to use an USB Blaster cable in Ubuntu you need to setup two urules files. The script **jtblaster** does that for you.