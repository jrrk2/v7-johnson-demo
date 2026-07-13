#!/bin/bash
# R0 open flow for the pure-wire uart loopback (no clock/logic).  Frames are
# assembled with the COMPLETE ~/prjxray database (deps copy lacks the LIOI
# ILOGIC section), per the ZINV_D investigation.
set -eu
ROOT=/home/jonathan/v7-johnson-demo; ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2
$YOSYS $ETH/r0_wireloop_yosys.ys > /tmp/r0_wireloop_yosys.log 2>&1 \
  || { echo YOSYS FAILED; tail -20 /tmp/r0_wireloop_yosys.log; exit 1; }
echo yosys OK
python3 $ETH/stamp_placement.py /tmp/r0_wireloop.json $ETH/placement_wireloop.txt /tmp/r0_wireloop_stamped.json
PIP_BLACKLIST=${PIP_BLACKLIST:-$ROOT/ibexsoc/openflow/pip_blacklist_int_r_bounce.txt}
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  NEXTPNR_PIP_BLACKLIST=$PIP_BLACKLIST \
  $NEXTPNR --chipdb $CHIPDB --xdc $ETH/wireloop_pins.xdc --json /tmp/r0_wireloop_stamped.json \
    --fasm /tmp/r0_wireloop.fasm --freq 50 --router router2 --placer sa \
    > /tmp/r0_wireloop_npnr.log 2>&1 || { echo NEXTPNR FAILED; tail -25 /tmp/r0_wireloop_npnr.log; exit 1; }
echo nextpnr OK
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $HOME/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/r0_wireloop.fasm /tmp/r0_wireloop.frames > /tmp/r0_wireloop_f2f.log 2>&1 \
  && echo frames OK || { echo F2F FAILED; tail /tmp/r0_wireloop_f2f.log; exit 1; }
$HOME/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/r0_wireloop.frames --output_file /tmp/r0_wireloop.bit \
  > /tmp/r0_wireloop_f2b.log 2>&1 && echo bit OK || { echo F2B FAILED; tail /tmp/r0_wireloop_f2b.log; exit 1; }
ls -l /tmp/r0_wireloop.bit | awk '{print "WIRELOOP OPEN BIT:",$5,"bytes"}'; echo R0_WIRELOOP_DONE
