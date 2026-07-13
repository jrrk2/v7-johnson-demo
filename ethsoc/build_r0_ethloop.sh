#!/bin/bash
# R0 hybrid flow, flat50 variant: the CPU runs on a 50 MHz clock derived from
# the board SYSCLK (a second MMCM, RST=rst_IBUF, self-starting) instead of the
# GT txoutclk -- so the processor boots independent of SGMII/GT bring-up (the
# 125 MHz GT domain is minimised to the PCS/PMA).  Matches firmware's
# "115200 @ 50 MHz" assumption.  Same open steps as build_r0.sh.
#   yosys pass-through -> stamp placement_flat50 -> nextpnr route -> fasm2frames
#   -> splice GT frames -> xc7frames2bit.   Output: /tmp/r0_ethloop.bit
set -eu
ROOT=/home/jonathan/v7-johnson-demo
ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

$YOSYS $ETH/r0_ethloop_yosys.ys > /tmp/r0_ethloop_yosys.log 2>&1 \
  || { echo "YOSYS FAILED"; tail -20 /tmp/r0_ethloop_yosys.log; exit 1; }
echo "yosys OK"
python3 $ETH/stamp_placement.py /tmp/r0_ethloop.json $ETH/placement_ethloop.txt /tmp/r0_ethloop_stamped.json
# Avoid the 6 mis-encoded INT_R bounce-pip encodings (prjxray subset-alias bug,
# convicted on ibex by on-board ddmin) that silently mis-route on silicon.
PIP_BLACKLIST=${PIP_BLACKLIST:-$ROOT/ibexsoc/openflow/pip_blacklist_int_r_bounce.txt}
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 ${NEXTPNR_EXTRA_ENV:+$NEXTPNR_EXTRA_ENV} NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  NEXTPNR_PIP_BLACKLIST=$PIP_BLACKLIST \
  $NEXTPNR --chipdb $CHIPDB --xdc ${ETHLOOP_XDC:-$ETH/r0_pins.xdc} --json /tmp/r0_ethloop_stamped.json \
    --fasm /tmp/r0_ethloop.fasm --write /tmp/r0_ethloop_routed.json --freq 50 --router router2 --placer sa \
    > /tmp/r0_ethloop_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -25 /tmp/r0_ethloop_npnr.log; exit 1; }
grep -iE "Max frequency|Routing complete|failed|unrouted" /tmp/r0_ethloop_npnr.log | tail -5
echo "nextpnr OK"
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $HOME/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/r0_ethloop.fasm /tmp/r0_ethloop.frames > /tmp/r0_ethloop_f2f.log 2>&1 \
  && echo "frames OK" || { echo "F2F FAILED"; tail /tmp/r0_ethloop_f2f.log; exit 1; }
python3 $ETH/splice_gt_frames.py $ETH/golden_ethsoc.bits /tmp/r0_ethloop.frames /tmp/r0_ethloop_spliced.frames
$HOME/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/r0_ethloop_spliced.frames --output_file /tmp/r0_ethloop.bit \
  > /tmp/r0_ethloop_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; tail /tmp/r0_ethloop_f2b.log; exit 1; }
ls -l /tmp/r0_ethloop.bit | awk '{print "ETHLOOP BIT:",$5,"bytes"}'
echo "R0_ETHLOOP_DONE"
