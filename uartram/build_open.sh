#!/bin/bash
# Autonomous open-flow (openXC7) build of the multi-digit calculator + checks.
# Vivado synth -> EDIF -> SVS json -> nextpnr-xilinx (router1) -> fasm -> frames -> bit
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

say "1/5 Vivado synth -> EDIF"
/opt/Xilinx/Vivado/2020.1/bin/vivado -mode batch -source vivado_edif.tcl -nojournal -log /tmp/uo_edif.log >/tmp/uo_edif.out 2>&1
grep -E "RAMB18:|UARTRAM_EDIF_DONE|ERROR:" /tmp/uo_edif.out | grep -v puts || { echo "EDIF FAILED"; exit 1; }

say "2/5 SVS read_edif -> nextpnr json"
$SVS script edif_to_nextpnr.lua $SVSDIR >/tmp/uo_svs.out 2>&1
tail -3 /tmp/uo_svs.out
test -s /tmp/uartram.json || { echo "JSON FAILED"; exit 1; }

say "3/5 nextpnr-xilinx (router1, flock-serialized)"
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_SKIP_FAILED_ARCS=1 \
  $NEXTPNR --router router1 --chipdb $CHIPDB --xdc top.xdc \
    --json /tmp/uartram.json --fasm /tmp/uartram_open.fasm --freq 200 \
    >/tmp/uo_npnr.out 2>&1
echo "nextpnr exit=$?"
test -s /tmp/uartram_open.fasm || { echo "FASM FAILED"; exit 1; }

say "4/5 fasm2frames"
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $F2F --db-root $PXDB --part $PART \
  /tmp/uartram_open.fasm /tmp/uartram_open.frames >/tmp/uo_f2f.out 2>&1 && echo "frames OK" || { echo "F2F FAILED"; tail /tmp/uo_f2f.out; exit 1; }

say "5/5 frames2bit"
$F2B --part_file $PXDB/$PART/part.yaml --part_name $PART \
  --frm_file /tmp/uartram_open.frames --output_file /tmp/uartram_open.bit >/tmp/uo_f2b.out 2>&1 && echo "bit OK" || { echo "F2B FAILED"; exit 1; }
ls -l /tmp/uartram_open.bit | awk '{print "OPEN BIT:",$5,"bytes"}'
echo "OPEN_FLOW_DONE"
