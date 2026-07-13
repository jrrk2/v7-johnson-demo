#!/bin/bash
# Macro-merge open flow pilot: reflectm = fresh yosys user logic (word-level
# MAC-swap reflector, msoc FIFO halves) + frozen Vivado eth_macro.
#   yosys (user synth + macro netlist pass-through)
#   -> stamp macro placement only (placement_macro.txt; user cells placed by
#      nextpnr SA)
#   -> nextpnr with --fixed-routes eth_macro_prefixed.routes (macro-internal
#      routing locked; requires the canonicalWireId + normalised-net-name
#      patches in nextpnr applyFixedRoutes)
#   -> fasm (+ IBUFDS_GTE2 defaults) -> frames -> bit (GT from DB, no splice)
set -eu
ROOT=/home/jonathan/v7-johnson-demo
ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

$YOSYS $ETH/r0_arpm.ys > /tmp/r0_arpm_yosys.log 2>&1 \
  || { echo "YOSYS FAILED"; tail -20 /tmp/r0_arpm_yosys.log; exit 1; }
python3 $ETH/merge_json_modules.py /tmp/arpm_user.json /tmp/arpm_macro.json /tmp/arpm_pre.json
$YOSYS $ETH/r0_arpm_merge.ys > /tmp/r0_arpm_merge.log 2>&1 \
  || { echo "YOSYS MERGE FAILED"; tail -20 /tmp/r0_arpm_merge.log; exit 1; }
echo "yosys OK"

# macro placement only (u_macro/* names match yosys's flattened u_macro.*)
# macro instance path in THIS design: framing_top instance 'eth' -> eth_macro1
sed 's|^\([^#[:space:]]\)|eth/eth_macro1/\1|' $ETH/eth_macro.routes > /tmp/eth_macro_arpm.routes
sed 's|^u_macro/|eth/eth_macro1/|' $ETH/placement_macro.txt > /tmp/placement_arpm.txt

python3 $ETH/stamp_placement.py /tmp/r0_arpm.json /tmp/placement_arpm.txt /tmp/r0_arpm_stamped.json /tmp/eth_macro_arpm.routes

PIP_BLACKLIST=${PIP_BLACKLIST:-$ROOT/ibexsoc/openflow/pip_blacklist_int_r_bounce.txt}
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_EXCLUDE_STAMPED_BBOX=1 ${NEXTPNR_EXTRA_ENV:+$NEXTPNR_EXTRA_ENV} NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  NEXTPNR_PIP_BLACKLIST=$PIP_BLACKLIST \
  $NEXTPNR --chipdb $CHIPDB --xdc $ETH/r0_pins.xdc --json /tmp/r0_arpm_stamped.json \
    --fixed-routes /tmp/eth_macro_arpm.routes \
    --fasm /tmp/r0_arpm.fasm --write /tmp/r0_arpm_routed.json --freq 50 --router router2 --placer sa \
    > /tmp/r0_arpm_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -25 /tmp/r0_arpm_npnr.log; exit 1; }
grep -iE "Max frequency|Routing complete|failed|unrouted|fixed-routes" /tmp/r0_arpm_npnr.log | tail -6
echo "nextpnr OK"

# inject the two always-on IBUFDS_GTE2 refclk-buffer defaults nextpnr omits
GTCOMMON=$(grep -oE "GTX_COMMON_X[0-9]+Y[0-9]+" /tmp/r0_arpm.fasm | head -1)
cp /tmp/r0_arpm.fasm /tmp/r0_arpm_final.fasm
if [ -n "$GTCOMMON" ]; then
  printf '%s.IBUFDS_GTE2_Y0.CLKCM_CFG\n%s.IBUFDS_GTE2_Y0.CLKRCV_TRST\n' "$GTCOMMON" "$GTCOMMON" \
    >> /tmp/r0_arpm_final.fasm
  echo "injected IBUFDS_GTE2 defaults for $GTCOMMON"
fi

XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $HOME/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/r0_arpm_final.fasm /tmp/r0_arpm.frames > /tmp/r0_arpm_f2f.log 2>&1 \
  && echo "frames OK (GT from DB, no splice)" || { echo "F2F FAILED"; tail /tmp/r0_arpm_f2f.log; exit 1; }

$HOME/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/r0_arpm.frames --output_file /tmp/r0_arpm.bit \
  > /tmp/r0_arpm_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; tail /tmp/r0_arpm_f2b.log; exit 1; }
ls -l /tmp/r0_arpm.bit | awk '{print "ARPM BIT:",$5,"bytes"}'
echo "R0_ARPM_DONE"
