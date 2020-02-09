#!/bin/bash

DUMP=
CHR_DUMP=NOCHR_DUMP
RAM_INFO=NORAM_INFO
FIRMWARE=gng_test.s
VGACONV=NOVGACONV
LOADROM=
FIRMONLY=NOFIRMONLY
MAXFRAME=
SIM_MS=1
SIMULATOR=iverilog
TOP=game_test
MIST=
MIST_PLL=
PLL_FILE=$JTROOT/modules/jtframe/hdl/clocking/fast_pll.v
SIMFILE=sim.f
MACROPREFIX=-D
EXTRA=
EXTRA_VHDL=
SHOWCMD=
ARGNUMBER=1
VIDEOWIDTH=256
VIDEOHEIGHT=224
SAMPLING_RATE=

rm -f test2.bin

function add_dir {
    if [ ! -d "$1" ]; then
        echo "ERROR: add_dir (sim.sh) failed because $1 is not a directory"
        exit 1
    fi
    processF=no
    echo "Adding dir $1 $2" >&2
    for i in $(cat $1/$2); do
        if [ "$i" = "-sv" ]; then 
            # ignore statements that iVerilog cannot understand
            continue; 
        fi
        if [ "$processF" = yes ]; then
            processF=no
            # echo $(dirname $i) >&2
            # echo $(basename $i) >&2
            dn=$(dirname $i)
            if [ "$dn" = . ]; then
                dn=$1
            fi
            add_dir $dn $(basename $i)
            continue
        fi
        if [[ "$i" = -F || "$i" == -f ]]; then
            processF=yes
            continue
        fi
        fn="$1/$i"
        if [ ! -e "$fn" ]; then
            (>&2 echo "Cannot find file $fn")
        fi
        echo $fn
    done
}

function get_named_arg {
    ARGNAME="$1"
    shift
    while [ $# -gt 0 ]; do
        if [ "$1" = "$ARGNAME" ]; then
            echo $2
            return
        fi
        shift
    done
}

# Which core is this for?
SYSNAME=$(get_named_arg -sysname $*)
MODULES=$(get_named_arg -modules $*)
JTFRAME=$MODULES/jtframe
PERCORE=

if [ "$MODULES" = "" ]; then
    echo "ERROR: Missing required argument -modules"
    exit 1
fi

# switch to NCVerilog if available
if which ncverilog; then
    SIMULATOR=ncverilog
    MACROPREFIX="+define+"
fi

if [ "$YM2203" = 1 ]; then
    echo "INFO: YM2203 support added."
    PERCORE="$PERCORE $(add_dir $MODULES/jt12/hdl jt03.f)"
fi

if [ "$MSM5205" = 1 ]; then
    echo "INFO: MSM5205 support added."
    PERCORE="$PERCORE $(add_dir $MODULES/jt5205/hdl jt5205.f)"
fi

if [ "$M6809" = 1 ]; then
    echo "INFO: M6809 support added."
    PERCORE="$PERCORE $MODULES/jtframe/hdl/cpu/mc6809i.v"
fi

if [ "$M6801" = 1 ]; then
    echo "INFO: M6801 support added."
    PERCORE="$PERCORE $MODULES/jtframe/hdl/cpu/6801_core.sv"
fi

if [ "$I8051" = 1 ]; then
    echo "INFO: i8051 support added."
    EXTRA_VHDL=$(add_dir $JTFRAME/hdl/cpu/8051 mc8051.f)
    # iVerilog cannot simulate the 8051 because it's in VHDL
    if [ $SIMULATOR = iverilog ]; then
        PERCORE="$PERCORE $JTFRAME/hdl/cpu/8051/dummy_8051.v"
    fi
    #echo $EXTRA_VHDL
fi

if [ "$YM2149" = 1 ]; then
    echo "INFO: YM2149 support added."
    PERCORE="$PERCORE $(add_dir $MODULES/jt12/jt49/hdl jt49.f)"
fi

if [ "$YM2151" = 1 ]; then
    echo "INFO: YM2151 support added."
    PERCORE="$PERCORE $(add_dir $MODULES/jt51/hdl jt51.f)"
fi

if [ "$MSM6295" = 1 ]; then
    echo "INFO: MSM6295 support added."
    PERCORE="$PERCORE $(add_dir $MODULES/jt6295/hdl jt6295.f)"
fi

case "$SYSNAME" in
    "")
        echo "ERROR: Needs system name. Use -sysname"
        exit 1;;
    popeye) PERCORE=$(add_dir $MODULES/jt49/hdl jt49.f)
            EXTRA="$EXTRA ${MACROPREFIX}POPEYECEN"
            ;;
esac
EXTRA="$EXTRA ${MACROPREFIX}GAME_ROM_PATH=\"${GAME_ROM_PATH}\""


while [ $# -gt 0 ]; do
case "$1" in
    "-showcmd") SHOWCMD="echo";;
    "-sysname") shift;; # ignore here
    "-modules") shift;; # ignore here
    "-w" | "-deep")
        DUMP=${MACROPREFIX}DUMP
        echo Signal dump enabled
        if [ $1 = "-deep" ]; then DUMP="$DUMP ${MACROPREFIX}DEEPDUMP"; fi
        ;;
    "-d")
        shift
        EXTRA="$EXTRA ${MACROPREFIX}$1"
        ;;
    -test)
        EXTRA="$EXTRA ${MACROPREFIX}DIP_TEST";;
    -pause)
        EXTRA="$EXTRA ${MACROPREFIX}DIP_PAUSE";;
    "-frame")
        shift
        if [ "$1" = "" ]; then
            echo "Must specify number of frames to simulate"
            exit 1
        fi
        MAXFRAME="${MACROPREFIX}MAXFRAME=$1"
        echo Simulate up to $1 frames
        ;;
    -srate)
        shift
        if [ "$1" = "" ]; then
            echo "Must specify the sampling rate"
            exit 1
        fi
        SAMPLING_RATE="-s $1"
        ;;
    #################### MiST setup
    "-mist")
        TOP=mist_test
        if [ $SIMULATOR = iverilog ]; then
            MIST=$(add_dir $JTFRAME/hdl/mist mist.f)
        else
            MIST="-F $JTFRAME/hdl/mist/mist.f"
        fi
        if [ -e $MODULES/jtgng_mist.sv ]; then
            # jtgng cores share a common MiST top file
            MISTTOP=$MODULES/jtgng_mist.sv
        else
            MISTTOP=$JTFRAME/hdl/mist/jtframe_mist_top.sv
        fi
        MIST="$JTFRAME/hdl/mist/mist_test.v $MISTTOP $MIST mist_dump.v"
        MIST="$MIST ${MACROPREFIX}MIST"
        # Add a local copy of mist_dump if it doesn't exist
        if [ ! -e mist_dump.v ]; then
            cp $JTFRAME/hdl/ver/mist_dump.v .
            git add -v mist_dump.v
        fi
        ;;
    #################### MiSTer setup
    -mister|-mr)
        TOP=mister_test
        if [ $SIMULATOR = iverilog ]; then
            MIST=$(add_dir $JTFRAME/hdl/mister mister.f)
        else
            MIST="-F $JTFRAME/hdl/mister/mister.f"
        fi

        if [ -e $JTROOT/hdl/jt${SYSNAME}.sv ]; then
            MISTTOP=../../hdl/jt${SYSNAME}_mister.sv
        else
            # jtgng cores share a common MiST top file
            MISTTOP=$MODULES/jtframe/hdl/mister/jtframe_emu.sv
            # Check if the conf_str.v file is present
            # and try to link to it if it is not here
            if [ ! -e conf_str.v ]; then
                if [ -e ../../mist/conf_str.v ]; then
                    ln -s ../../mist/conf_str.v
                fi
            fi
        fi
        MIST="$JTFRAME/hdl/mister/mister_test.v $MISTTOP $MIST mister_dump.v"
        MIST="$MIST ${MACROPREFIX}MISTER"
        # Add a local copy of mist_dump if it doesn't exist
        if [ ! -e mister_dump.v ]; then
            cp $JTFRAME/hdl/ver/mister_dump.v .
            git add -v mister_dump.v
        fi
        SIMFILE=sim_mister.f
        PLL_FILE=$JTROOT/modules/jtframe/hdl/mister/mister_pll48.v
        # Generate a fake build_id.v file
        echo "\`define BUILD_DATE \"190311\"" > build_id.v
        echo "\`define BUILD_TIME \"190311\"" >> build_id.v
        ;;
    ##########################
    "-slowpll")
        echo "INFO: Simulation will use the slow PLL model"
        MIST_PLL=altera_pll.f
        PLL_FILE="slow_pll.f"
        EXTRA="$EXTRA ${MACROPREFIX}SLOWPLL"
        ;;
    "-nosnd")
        EXTRA="$EXTRA ${MACROPREFIX}NOSOUND";;
    "-nocolmix")
        EXTRA="$EXTRA ${MACROPREFIX}NOCOLMIX";;
    "-noscr")
        EXTRA="$EXTRA ${MACROPREFIX}NOSCR";;
    "-nochar")
        EXTRA="$EXTRA ${MACROPREFIX}NOCHAR";;
    "-time")
        shift
        if [ "$1" = "" ]; then
            echo "Must specify number of milliseconds to simulate"
            exit 1
        fi
        SIM_MS="$1"
        echo Simulate $1 ms
        ;;
    "-firmonly")
        FIRMONLY=FIRMONLY
        echo Firmware dump only
        ;;
    "-t")
        # is there a file name?
        if [[ "${2:0:1}" != "-" && $# -gt 1  ]]; then
            shift
            FIRMWARE=$1
        else
            FIRMWARE=bank_check.s
        fi
        echo "Using test firmware $FIRMWARE"
        LOADROM="${MACROPREFIX}TESTROM ${MACROPREFIX}FIRMWARE_SIM"
        if ! z80asm $FIRMWARE -o test.bin -l &> $FIRMWARE.lst; then
            cat $FIRMWARE.lst
            exit 1
        fi
        ;;
    "-t2")
        # is there a file name?
        if [[ "${2:0:1}" != "-" && $# -gt 1  ]]; then
            shift
            FIRMWARE2=$1
        else
            FIRMWARE2=bank_check.s
        fi
        echo "Using test firmware $FIRMWARE2 for second CPU"
        LOADROM=${MACROPREFIX}TESTROM
        if ! z80asm $FIRMWARE2 -o test2.bin -l; then
            exit 1
        fi
        ;;
    "-info")
        RAM_INFO=RAM_INFO
        echo RAM information enabled
        ;;
    "-video")
        EXTRA="$EXTRA ${MACROPREFIX}DUMP_VIDEO"
        echo Video dump enabled
        if [ ${2:0:1} != - ]; then
            # get number of frames to simulate
            shift
            MAXFRAME="${MACROPREFIX}MAXFRAME=$1"
            echo Simulate up to $1 frames
        fi
        rm -f video.bin
        rm -f video*.jpg
        VIDEO_DUMP=TRUE
        ;;
    -videow)
        shift
        VIDEOWIDTH=$1
        ;;
    -videoh)
        shift
        VIDEOHEIGHT=$1
        ;;
    "-load")
        LOADROM=${MACROPREFIX}LOADROM
        echo ROM load through SPI enabled
        if [ ! -e $GAME_ROM_PATH ]; then
            echo "Missing file $GAME_ROM_PATH"
            exit 1
        fi
        ;;
    "-lint")
        SIMULATOR=verilator;;
    "-nc")
        SIMULATOR=ncverilog
        MACROPREFIX="+define+"
        if [ $ARGNUMBER != 1 ]; then
            echo "ERROR: -nc must be the first argument so macros get defined correctly"
            exit 1
        fi
        ;;
    "-help")
        cat << EOF
JT_GNG simulation tool. (c) Jose Tejada 2019, @topapate
    -d        Add specific Verilog macros for the simulation. Common options
        VIDEO_START=X   video output will start on frame X
        DUMP_START=X    waveform dump will start on frame X
        DIP_TEST        Enable the test bit (active low)
        SIM_INPUTS      Game cabinet inputs will be taken from a sim_inputs.hex
                        file. Each line contains a byte with the input status.
                        All bits are read as active high. They are inverted
                        if necessary by JTFRAME logic,
        DIP_PAUSE       Enable the DIP PAUSE bit (active low)
        TESTSCR1        disable scroll control by the CPU and scroll the
                        background automatically. It can be used together with
                        NOMAIN macro
        SDRAM_DELAY=X   ns delay for SDRAM_CLK (cannot use with -slowpll)
        BASE_CLK=X      Base period for game clock (cannot use with -slowpll)
        SIM_SCANDOUBLER Simulate scan doubler
        SIMULATE_OSD    Simulate OSD display
        SIMINFO         Show simulation options available thorugh define commands
        SCANDOUBLER_DISABLE=1   Disables the scan doubler module
    -deep     Save all signals for scope verification
    -frame    Number of frames to simulate
    -lint     Run verilator as lint tool
    -load     Load the ROM file using the SPI communication. Slower.
    -modules  Location of the modules folder with respect to the simulation folder
    -mist     Use MiST setup for simulation, instead of using directly the
              game module. This is slower but more informative.
    -nc       Select NCVerilog as the simulator
    -nochar   Disable CHAR hardware. Faster simulation.
    -noscr    Disable SCROLL hardware. Faster simulation.
    -nosnd    Disable SOUND hardware. Speeds up simulation a lot!
    -pause    Enable pause DIP setting. Same as -d DIP_PAUSE
    -srate    Sampling rate of the .wav file
    -t        Compile and load test file for main CPU. It can be used with the
              name of an assembly language file.
    -t2       Same as -t but for the sound CPU
    -time     Number of milliseconds to simulate
    -test     Enable test DIP setting. Same as -d DIP_TEST
    -slowpll  Simulate using Altera's model for PLLs
    -showcmd  Display the simulation command only. Do not run any simulation.
    -sysname  Specify the name of the core
    -video    Enable video output. Can be followed by a number to get
              the number of frames to simulate.
    -videow   Define the visible screen width  (only useful if -video is also used)
    -videoh   Define the visible screen height (only useful if -video is also used)
    -w        Save a small set of signals for scope verification
EOF
        exit 0
        ;;
    *) echo "Unknown option $1. Use -help to see the list of options"; exit 1;;
esac
    shift
    ARGNUMBER=$((ARGNUMBER+1))
done

if [ $FIRMONLY = FIRMONLY ]; then exit 0; fi

# Use this function to create
# HEX files with initial contents for some of the RAMs
function clear_hex_file {
    cnt=0
    rm -f $1.hex
    while [ $cnt -lt $2 ]; do
        echo 0 >> $1.hex
        cnt=$((cnt+1))
    done
}

if [ "$EXTRA" != "" ]; then
    echo Verilog macros: "$EXTRA"
fi

EXTRA="$EXTRA ${MACROPREFIX}MEM_CHECK_TIME=$MEM_CHECK_TIME ${MACROPREFIX}SYSTOP=jt${SYSNAME}_mist"
# macros for MiST
EXTRA="$EXTRA ${MACROPREFIX}GAMETOP=jt${SYSNAME}_game ${MACROPREFIX}MISTTOP=jt${SYSNAME}_mist"

# Add the PLL (MiST only)
if [[ $TOP = mist_test || $TOP = mister_test ]]; then
    if [ "$MIST_PLL" != "" ]; then
        # Adds the Altera file with the PLL models
        if [ $SIMULATOR = iverilog ]; then
            MIST="$MIST $(add_dir $JTFRAME/hdl/mist $MIST_PLL)"
        else
            MIST="$MIST -F $JTFRAME/hdl/mist/$MIST_PLL"
        fi
    fi
    # Adds the .f file with the PLL modules
    MIST="$MIST $PLL_FILE"
fi

case $SIMULATOR in
iverilog)
    $SHOWCMD iverilog -g2005-sv $MIST \
        -f game.f $PERCORE \
        $(add_dir $JTFRAME/hdl/ver $SIMFILE ) \
        $JTFRAME/hdl/cpu/tv80/*.v  \
        -s $TOP -o sim -DSIM_MS=$SIM_MS -DSIMULATION \
        $DUMP -D$CHR_DUMP -D$RAM_INFO -D$VGACONV $LOADROM \
        $MAXFRAME -DIVERILOG $EXTRA \
    || exit 1
    $SHOWCMD sim -lxt;;
ncverilog)
    $SHOWCMD ncverilog +access+r +nc64bit +define+NCVERILOG \
        -f game.f $PERCORE \
        -F $JTFRAME/hdl/ver/$SIMFILE -disable_sem2009 $MIST \
        +define+SIM_MS=$SIM_MS +define+SIMULATION \
        $DUMP $LOADROM \
        $MAXFRAME \
        -ncvhdl_args,-V93 $JTFRAME/hdl/cpu/t80/T80{pa,_ALU,_Reg,_MCode,"",s}.vhd \
        $EXTRA_VHDL \
        $JTFRAME/hdl/cpu/tv80/*.v \
        $EXTRA -l /dev/null || exit $?;;
verilator)
    $SHOWCMD verilator -I../../hdl \
        -f game.f $PERCORE \
        $MODULES/tv80/*.v \
        $MODULES/ver/quick_sdram.v \
        --top-module jt${SYSNAME}_game -o sim \
        $DUMP -D$CHR_DUMP -D$RAM_INFO -D$VGACONV $LOADROM -DFASTSDRAM \
        -DVERILATOR_LINT \
        $MAXFRAME -DSIM_MS=$SIM_MS --lint-only $EXTRA;;
esac

if [ "$VIDEO_DUMP" = TRUE ]; then
# convert -size 384x240 -depth 8 RGBA:video.raw -resize 200% video.png
    convert $CONVERT_OPTIONS -size ${VIDEOWIDTH}x${VIDEOHEIGHT} \
        -depth 8 RGBA:video.raw video.jpg
fi

# convert raw sound file to wav format
if [ -e sound.raw ]; then
    $JTFRAME/bin/raw2wav $SAMPLING_RATE < sound.raw
fi
