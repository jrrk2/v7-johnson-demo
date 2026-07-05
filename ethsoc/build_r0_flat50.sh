#!/bin/bash
# R0 hybrid flow, flat50 variant: the CPU runs on a 50 MHz clock derived from
# the board SYSCLK (a second MMCM, RST=rst_IBUF, self-starting) instead of the
# GT txoutclk -- so the processor boots independent of SGMII/GT bring-up (the
# 125 MHz GT domain is minimised to the PCS/PMA).  Matches firmware's
# "115200 @ 50 MHz" assumption.  Same open steps as build_r0.sh.
#   yosys pass-through -> stamp placement_flat50 -> nextpnr route -> fasm2frames
#   -> splice GT frames -> xc7frames2bit.   Output: /tmp/r0_ethsoc_flat50.bit
set -eu
ROOT=/home/jonathan/v7-johnson-demo
ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$ROOT/deps/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

$YOSYS $ETH/r0_flat50_yosys.ys > /tmp/r0_flat50_yosys.log 2>&1 \
  || { echo "YOSYS FAILED"; tail -20 /tmp/r0_flat50_yosys.log; exit 1; }
echo "yosys OK"
python3 $ETH/stamp_placement.py /tmp/r0_ethsoc_flat50.json $ETH/placement_flat50.txt /tmp/r0_flat50_stamped.json
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  $NEXTPNR --chipdb $CHIPDB --xdc $ETH/r0_pins.xdc --json /tmp/r0_flat50_stamped.json \
    --fasm /tmp/r0_ethsoc_flat50.fasm --freq 50 --router router2 --placer sa \
    > /tmp/r0_flat50_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -25 /tmp/r0_flat50_npnr.log; exit 1; }
grep -iE "Max frequency|Routing complete|failed|unrouted" /tmp/r0_flat50_npnr.log | tail -5
echo "nextpnr OK"
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $ROOT/deps/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/r0_ethsoc_flat50.fasm /tmp/r0_flat50.frames > /tmp/r0_flat50_f2f.log 2>&1 \
  && echo "frames OK" || { echo "F2F FAILED"; tail /tmp/r0_flat50_f2f.log; exit 1; }
python3 $ETH/splice_gt_frames.py $ETH/golden_ethsoc.bits /tmp/r0_flat50.frames /tmp/r0_flat50_spliced.frames
$ROOT/deps/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/r0_flat50_spliced.frames --output_file /tmp/r0_ethsoc_flat50.bit \
  > /tmp/r0_flat50_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; tail /tmp/r0_flat50_f2b.log; exit 1; }
ls -l /tmp/r0_ethsoc_flat50.bit | awk '{print "ETHSOC FLAT50 BIT:",$5,"bytes"}'
echo "R0_FLAT50_DONE"
