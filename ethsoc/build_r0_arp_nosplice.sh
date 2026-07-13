#!/bin/bash
# R0 open flow, SPLICE-FREE GT variant.  Identical to build_r0_arp.sh up to
# the fasm, but the GTX quad-113 configuration is now emitted by fasm2frames
# straight from the prjxray DB instead of being spliced from the golden bits.
#
# What made this possible (all validated bit-exact vs golden_ethsoc.bits, 355/355
# GT config bits, only the 4 GT frames 0x00424C9C..9F touched):
#   1. tilegrid.json: added CLB_IO_CLK frame addressing for the two GT tiles the
#      design uses -- GTX_CHANNEL_1_X394Y17 (base 0x00424C80, offset 22) and
#      GTX_COMMON_X394Y23 (base 0x00424C80, offset 0).  prjxray shipped bits:{}
#      for every GTX tile, so fasm2frames knew the segbits but not the frame.
#   2. ppips_gtx_common.db: removed the IBUFDS_GTE2_Y{0,1}.CLKCM_CFG / .CLKRCV_TRST
#      'always' lines -- they shadowed the real segbits (30_1482 / 30_1484), the
#      same ppip-shadows-segbit class of bug as LIOI ZINV_D.
#   3. nextpnr omits the two always-on IBUFDS_GTE2 refclk-buffer defaults
#      (CLKCM_CFG, CLKRCV_TRST) that Vivado sets for any used GT refclk buffer
#      (cf. the FDSE INIT=1 default) -- injected here after nextpnr.
set -eu
ROOT=/home/jonathan/v7-johnson-demo
ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

$YOSYS $ETH/r0_arp_nosplice.ys > /tmp/r0_arp_yosys.log 2>&1 \
  || { echo "YOSYS FAILED"; tail -20 /tmp/r0_arp_yosys.log; exit 1; }
echo "yosys OK"
python3 $ETH/stamp_placement.py /tmp/r0_arp.json $ETH/placement_arp.txt /tmp/r0_arp_stamped.json
PIP_BLACKLIST=${PIP_BLACKLIST:-$ROOT/ibexsoc/openflow/pip_blacklist_int_r_bounce.txt}
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 ${NEXTPNR_EXTRA_ENV:+$NEXTPNR_EXTRA_ENV} NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  NEXTPNR_PIP_BLACKLIST=$PIP_BLACKLIST \
  $NEXTPNR --chipdb $CHIPDB --xdc ${ETHLOOP_XDC:-$ETH/r0_pins.xdc} --json /tmp/r0_arp_stamped.json \
    --fasm /tmp/r0_arp.fasm --write /tmp/r0_arp_routed.json --freq 50 --router router2 --placer sa \
    > /tmp/r0_arp_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -25 /tmp/r0_arp_npnr.log; exit 1; }
grep -iE "Max frequency|Routing complete|failed|unrouted" /tmp/r0_arp_npnr.log | tail -5
echo "nextpnr OK"

# --- inject the two always-on IBUFDS_GTE2 refclk-buffer defaults nextpnr omits.
#     Derive the GTX_COMMON tile instance from the fasm so this isn't hard-wired.
GTCOMMON=$(grep -oE "GTX_COMMON_X[0-9]+Y[0-9]+" /tmp/r0_arp.fasm | head -1)
cp /tmp/r0_arp.fasm /tmp/r0_arp_nosplice.fasm
if [ -n "$GTCOMMON" ]; then
  printf '%s.IBUFDS_GTE2_Y0.CLKCM_CFG\n%s.IBUFDS_GTE2_Y0.CLKRCV_TRST\n' "$GTCOMMON" "$GTCOMMON" \
    >> /tmp/r0_arp_nosplice.fasm
  echo "injected IBUFDS_GTE2 defaults for $GTCOMMON"
fi

XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $HOME/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/r0_arp_nosplice.fasm /tmp/r0_arp.frames > /tmp/r0_arp_f2f.log 2>&1 \
  && echo "frames OK (GT from DB, no splice)" || { echo "F2F FAILED"; tail /tmp/r0_arp_f2f.log; exit 1; }

$HOME/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/r0_arp.frames --output_file /tmp/r0_arp_nosplice.bit \
  > /tmp/r0_arp_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; tail /tmp/r0_arp_f2b.log; exit 1; }
ls -l /tmp/r0_arp_nosplice.bit | awk '{print "NOSPLICE BIT:",$5,"bytes"}'
echo "R0_ETHLOOP_NOSPLICE_DONE"
