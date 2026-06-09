#!/bin/bash
# Open-flow (openXC7) build of the multi-digit calculator on the USER_CLOCK
# (Si570, AK34/AL34) at its 156.25 MHz default, NO PLL, baud 115200 (BAUDDIV=85).
# Vivado synth (USE_USERCLK) -> EDIF -> SVS json -> nextpnr-xilinx (router1)
#   -> fasm -> frames -> bit  ->  /tmp/uartram_uc_open.bit
set -u
ROOT=/home/jonathan/v7-johnson-demo
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
SVS=$ROOT/deps/System-Verilog-suite/_build/default/sv_suite.exe
SVSDIR=$ROOT/deps/System-Verilog-suite
PXPY=$ROOT/deps/prjxray/env/bin/python
F2F=$ROOT/deps/prjxray/utils/fasm2frames.py
F2B=$ROOT/deps/prjxray/build/tools/xc7frames2bit
PXDB=$ROOT/deps/prjxray/database/virtex7
PART=xc7vx485tffg1761-2
cd $ROOT/uartram
say(){ echo "===== $* ====="; }

say "1/5 Vivado synth (USE_USERCLK, BAUDDIV=85) -> EDIF"
/opt/Xilinx/Vivado/2020.1/bin/vivado -mode batch -source vivado_edif_userclk.tcl -nojournal -log /tmp/uo_uc_edif.log >/tmp/uo_uc_edif.out 2>&1
grep -E "RAMB18:|UARTRAM_EDIF_DONE|ERROR:" /tmp/uo_uc_edif.out | grep -v puts || { echo "EDIF FAILED"; tail -8 /tmp/uo_uc_edif.out; exit 1; }

say "2/5 SVS read_edif -> nextpnr json"
$SVS script edif_to_nextpnr.lua $SVSDIR >/tmp/uo_uc_svs.out 2>&1
tail -3 /tmp/uo_uc_svs.out
test -s /tmp/uartram.json || { echo "JSON FAILED"; exit 1; }

say "3/5 nextpnr-xilinx (router2, flock-serialized, userclk 156.25MHz)"
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 \
  $NEXTPNR --router router2 --seed 4 --chipdb $CHIPDB --xdc top.xdc \
    --json /tmp/uartram.json --fasm /tmp/uartram_uc_open.fasm --freq 156 \
    >/tmp/uo_uc_npnr.out 2>&1
echo "nextpnr exit=$?"
grep -iE "Max frequency|Routing complete|failed|unrouted|error" /tmp/uo_uc_npnr.out | tail -5
test -s /tmp/uartram_uc_open.fasm || { echo "FASM FAILED"; exit 1; }

say "4/5 fasm2frames"
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $F2F --db-root $PXDB --part $PART \
  /tmp/uartram_uc_open.fasm /tmp/uartram_uc_open.frames >/tmp/uo_uc_f2f.out 2>&1 && echo "frames OK" || { echo "F2F FAILED"; tail /tmp/uo_uc_f2f.out; exit 1; }

say "4b/5 patch rx IOB (prjxray AU33 LVCMOS18 input segbit gap)"
$PXPY $ROOT/uartram/patch_rx_iob.py /tmp/uartram_uc_open.frames /tmp/uartram_uc_open_rx.frames && mv /tmp/uartram_uc_open_rx.frames /tmp/uartram_uc_open.frames

say "5/5 frames2bit"
$F2B --part_file $PXDB/$PART/part.yaml --part_name $PART \
  --frm_file /tmp/uartram_uc_open.frames --output_file /tmp/uartram_uc_open.bit >/tmp/uo_uc_f2b.out 2>&1 && echo "bit OK" || { echo "F2B FAILED"; exit 1; }
ls -l /tmp/uartram_uc_open.bit | awk '{print "OPEN UC BIT:",$5,"bytes"}'
echo "OPEN_FLOW_UC_DONE"
