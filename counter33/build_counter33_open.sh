#!/bin/bash
# Open-flow build of counter33 (33-bit SYSCLK CARRY4 counter -> 8 LEDs).
# Pure fresh RTL (no Vivado netlist / no stamping): yosys synth_xilinx ->
# nextpnr-xilinx (fresh place+route) -> fasm2frames -> xc7frames2bit.
# A minimal end-to-end CARRY4 regression check for the open flow.
#   Output: /tmp/counter33.bit
set -eu
ROOT=/home/jonathan/v7-johnson-demo
CTR=$ROOT/counter33
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

# 1. synth fresh RTL -> nextpnr json (CARRY4 inferred from the + operator)
$YOSYS -p "
read_verilog $CTR/counter33.v
synth_xilinx -flatten -family xc7
write_json /tmp/counter33.json
stat
" > /tmp/counter33_yosys.log 2>&1 || { echo "YOSYS FAILED"; tail -20 /tmp/counter33_yosys.log; exit 1; }
grep -iE "CARRY4|FDRE|LUT" /tmp/counter33_yosys.log | tail -6
echo "yosys OK"

# 2. nextpnr fresh place+route (200 MHz sysclk)
#   * NEXTPNR_CARRY_COUNTER_FIX=1: co-locate each sum FF into its CARRY4 slice so
#     the cnt[i]->S[i] counter feedback stays intra-slice.
#   * --placer heap: the SA placer does NOT honour the created S-feed-through LUT
#     cluster constraints (feed-through lands slices away from its CARRY4 -> the
#     unroutable "cnt[i]$legal O6->O6" arc); HeAP honours constr_parent/constr_z
#     and keeps the feed-through in the carry's own D6LUT.
flock /tmp/nextpnr.lock env NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 NEXTPNR_CARRY_COUNTER_FIX=1 \
  $NEXTPNR --chipdb $CHIPDB --xdc $CTR/counter33.xdc --json /tmp/counter33.json \
    --fasm /tmp/counter33.fasm --freq 200 --router router2 --placer heap \
    > /tmp/counter33_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -25 /tmp/counter33_npnr.log; exit 1; }
grep -iE "Max frequency|Info: Device utilisation|failed|unrouted|Routing complete" /tmp/counter33_npnr.log | tail -5
echo "nextpnr OK"

# 3. FASM -> frames -> bit
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $HOME/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/counter33.fasm /tmp/counter33.frames \
  > /tmp/counter33_f2f.log 2>&1 && echo "frames OK" || { echo "F2F FAILED"; tail /tmp/counter33_f2f.log; exit 1; }
$HOME/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/counter33.frames --output_file /tmp/counter33.bit \
  > /tmp/counter33_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; tail /tmp/counter33_f2b.log; exit 1; }
ls -l /tmp/counter33.bit | awk '{print "COUNTER33 BIT:",$5,"bytes"}'
echo "COUNTER33_DONE"
