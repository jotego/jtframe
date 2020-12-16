#!/bin/bash


SIM=iverilog
#SIM=cvc64

if [ $SIM = iverilog ]; then
    MACRO=-D
    PARAM=-P
    EXTRA=
    EXTRA2=-lxt
else
    MACRO=+define+
    PARAM=+param+
    EXTRA="+dump2fst +fst+parallel2=on"
    EXTRA2=
fi
SDRAM_SHIFT=0
DUMP=${MACRO}DUMP

while [ $# -gt 0 ]; do
    case $1 in
        -nodump) DUMP=;;
        -mister) EXTRA="$EXTRA ${MACRO}MISTER ${MACRO}JTFRAME_SDRAM_ADQM";;
        -mist) ;;
        -time)
            shift
            EXTRA="$EXTRA ${MACRO}SIM_TIME=${1}_000_000";;
        -period)
            shift
            EXTRA="$EXTRA ${MACRO}PERIOD=$1";;
        -readonly)
            EXTRA="$EXTRA ${MACRO}WRITE_ENABLE=0";;
        -norefresh)
            EXTRA="$EXTRA ${MACRO}NOREFRESH";;
        -repack)
            EXTRA="$EXTRA ${MACRO}JTFRAME_SDRAM_REPACK";;
        -write)
            shift
            EXTRA="$EXTRA ${MACRO}WRITE_CHANCE=$1";;
        -safe)
            EXTRA="$EXTRA ${MACRO}JTFRAME_SDRAM_ADQM_SAFE";;
        -idle)
            shift
            EXTRA="$EXTRA ${PARAM}test.IDLE=$1";;
        -1banks)
            EXTRA="$EXTRA ${PARAM}test.BANK3=0 ${PARAM}test.BANK2=0 ${PARAM}test.BANK1=0";;
        -2banks)
            EXTRA="$EXTRA ${PARAM}test.BANK3=0 ${PARAM}test.BANK2=0";;
        -3banks)
            EXTRA="$EXTRA ${PARAM}test.BANK3=0";;
        -4banks)
            ;;
        -shift)
            shift
            SDRAM_SHIFT=$1;;
        -nohold)
            EXTRA="$EXTRA ${MACRO}JTFRAME_NOHOLDBUS";;
        -perf)
            EXTRA="$EXTRA ${MACRO}WRITE_ENABLE=0 ${PARAM}test.IDLE=0 ${MACRO}NOREFRESH";;
        -h|-help) cat << EOF
    Tests that correct values are written and read. It also tests that there are no stall conditions.
    All is done in a random test.
Usage:
    -nodump       disables waveform dumping
    -time val     simulation time in ms (5ms by default)
    -period       defines clock period (default 7.5ns = 133MHz)
                  10.416 for 96MHz
                  7.5ns sets the maximum speed before breaking SDRAM timings
    -readonly     disables write requests
    -repack       repacks output data, adding one stage of latching (defines JTFRAME_SDRAM_REPACK)
    -safe         blocks a wider window in MiSTer mode
    -nohold       Leaves DQ bus floating during idle cycles
    -norefresh    disables refresh
    -write        chance of a write in the writing bank. Integer between 0 and 100
    -idle         defines % of time idle for each bank requester. Use an integer between 0 and 100.
    -perf         Measures read performance: disables writes and refresh. Sets idle time to 0%.

    Bank options:
    -1banks       Only bank 0 is active
    -2banks       Only banks 0 and 1 are active
    -3banks       Only banks 0, 1 and 2 are active

    -mister       enables MiSTer simulation, with special constraint on DQM signals
    -mist         enables free use of DQM signals (default)
EOF
        exit 1;;
    *)  echo "Unexpected argument $1"
        exit 1;;
    esac
    shift
done

make || exit $?

echo Extra arguments: "$EXTRA"
$SIM test.v ../../hdl/sdram/jtframe_sdram_bank*.v ../../hdl/ver/mt48lc16m16a2.v \
    -o sim ${MACRO}JTFRAME_SDRAM_test.BANKS ${MACRO}SIMULATION $DUMP $EXTRA \
    ${MACRO}SDRAM_SHIFT=$SDRAM_SHIFT \
&& sim $EXTRA2