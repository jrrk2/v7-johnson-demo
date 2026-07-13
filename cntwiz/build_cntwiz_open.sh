#!/bin/bash
# Open-flow (stamped) build of cntwiz: Clocking-Wizard MMCM (200->50 MHz) + a
# 26-bit CARRY4 counter -> LEDs (led[7]=locked, led[6:0]=cnt taps, visibly
# blinking).  The INTENDED CARRY4 open-flow verification: Vivado placement
# (placement_cntwiz.txt, CARRY4+S-LUT+FF co-located per slice) stamped into the
# netlist, nextpnr ROUTES only (stamp_placement.py inserts the S/DI route-thru
# LUTs the fresh-synth path lacks), fasm2frames -> xc7frames2bit.
#   Output: /tmp/cntwiz_open.bit
set -eu
ROOT=/home/jonathan/v7-johnson-demo
CW=$ROOT/cntwiz
ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

# 1. netlist -> nextpnr json
$YOSYS -p "
read_verilog -lib +/xilinx/cells_sim.v
read_verilog -lib +/xilinx/cells_xtra.v
read_verilog $CW/cntwiz_netlist_y.v
hierarchy -top cnt_top
proc
flatten
clean
delete t:\$scopeinfo
blackbox =* cnt_top %d
stat
write_json /tmp/cntwiz.json
" > /tmp/cntwiz_yosys.log 2>&1 || { echo "YOSYS FAILED"; tail -20 /tmp/cntwiz_yosys.log; exit 1; }
grep -iE "CARRY4|FDRE|MMCME2" /tmp/cntwiz_yosys.log | tail -4
echo "yosys OK"

# 2. stamp Vivado placement (BEL attrs + CARRY4-S/DI/5FF route-thru LUT1s)
python3 $ETH/stamp_placement.py /tmp/cntwiz.json $CW/placement_cntwiz.txt /tmp/cntwiz_stamped.json \
  > /tmp/cntwiz_stamp.log 2>&1 || { echo "STAMP FAILED"; tail /tmp/cntwiz_stamp.log; exit 1; }
grep -iE "stamped|routethru" /tmp/cntwiz_stamp.log | tail -4

# 3. nextpnr routes the stamped placement
flock /tmp/nextpnr.lock env NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  $NEXTPNR --chipdb $CHIPDB --xdc $CW/cnt.xdc --json /tmp/cntwiz_stamped.json \
    --fasm /tmp/cntwiz.fasm --freq 50 --router router2 --placer sa \
    > /tmp/cntwiz_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -25 /tmp/cntwiz_npnr.log; exit 1; }
grep -iE "Max frequency|Routing complete|failed|unrouted" /tmp/cntwiz_npnr.log | tail -4
echo "nextpnr OK"

# 4. FASM -> frames -> bit
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $HOME/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/cntwiz.fasm /tmp/cntwiz.frames \
  > /tmp/cntwiz_f2f.log 2>&1 && echo "frames OK" || { echo "F2F FAILED"; tail /tmp/cntwiz_f2f.log; exit 1; }
$HOME/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/cntwiz.frames --output_file /tmp/cntwiz_open.bit \
  > /tmp/cntwiz_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; tail /tmp/cntwiz_f2b.log; exit 1; }
ls -l /tmp/cntwiz_open.bit | awk '{print "CNTWIZ OPEN BIT:",$5,"bytes"}'
echo "CNTWIZ_DONE"
