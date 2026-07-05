#!/bin/bash
# R0 hybrid flow: Vivado PLACEMENT (vendored placement_flat.txt) + nextpnr
# ROUTING + open bitgen.  No Vivado/RapidWright in the loop -- the flat
# netlist, placement dump and GT frames are one-time vendored artifacts.
#
#   yosys (pass-through, no synth) -> stamp_placement.py (BEL attrs,
#   pad-buffer stitch, routethru LUT1s) -> nextpnr --placer sa (route-only
#   in effect) -> fasm2frames -> splice_gt_frames -> xc7frames2bit
#
# STATUS: builds + routes + encodes; board still dark (see task #14 /
# ethsoc-phase-b-progress memory for the remaining suspect list).
set -eu
ROOT=/home/jonathan/v7-johnson-demo
ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$ROOT/deps/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

$YOSYS $ETH/r0_yosys.ys
python3 $ETH/stamp_placement.py /tmp/r0_ethsoc.json $ETH/placement_flat.txt /tmp/r0_stamped.json
# NEXTPNR_ALLOW_CO_5FF_CONTENTION: the CO-fabric-vs-5FF-xMUX validity check
# guards nextpnr's *own* placer; here placement is Vivado's (stamped), so its
# legally-co-located CO+5FF slices must be accepted (see arch_place.cc).
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  $NEXTPNR --chipdb $CHIPDB --xdc $ETH/r0_pins.xdc --json /tmp/r0_stamped.json \
    --fasm /tmp/r0_ethsoc.fasm --freq 125 --router router2 --placer sa
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $ROOT/deps/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/r0_ethsoc.fasm /tmp/r0.frames
python3 $ETH/splice_gt_frames.py $ETH/golden_ethsoc.bits /tmp/r0.frames /tmp/r0_spliced.frames
$ROOT/deps/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/r0_spliced.frames --output_file /tmp/r0_ethsoc.bit
echo "R0 bit: /tmp/r0_ethsoc.bit"
