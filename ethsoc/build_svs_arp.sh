#!/bin/bash
# Fully-open eth-arp bitstream for the VC707 — no Vivado anywhere.
# VALIDATED ON SILICON 2026-07-13 (ARP 9/9 @ 0.21ms):
#   vc707_arp_netlist_y.v (Vivado post-synth netlist, checked in)
#     -> yosys (viv2json.ys)                        netlist json
#   prjxray tilegrid -> gen_floorplan.py            site floorplan
#     -> SVS place_lef  (SA topo place, carry anchors, physical BRAM coords,
#                        control-buffer tiers, LUT1 relays)
#     -> carry_stamp.py (carry-slice completion: S/DI buffers, pin-aligned
#                        DIrt, LUT-fracture legality, sum-FF slots)
#     -> nextpnr-xilinx router2                     fasm
#     -> fasm2frames + xc7frames2bit                bitstream
# Env overrides: SVS, YOSYS, PRJXRAY, OUT (defaults below).  macOS: no flock.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ETH=$ROOT/ethsoc
SVS=${SVS:-$HOME/System-Verilog-suite}
YOSYS=${YOSYS:-yosys}
PRJXRAY=${PRJXRAY:-$HOME/prjxray}
PXDB=$PRJXRAY/database/virtex7
PART=xc7vx485tffg1761-2
NEXTPNR=${NEXTPNR:-$ROOT/deps/nextpnr-xilinx/build-opt/nextpnr-xilinx}
[ -x "$NEXTPNR" ] || NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
WORK=${WORK:-/tmp/svs_arp_build}
OUT=${OUT:-/tmp/svs_arp.bit}
mkdir -p "$WORK"
LOCK="flock /tmp/nextpnr.lock"; command -v flock >/dev/null || LOCK=""

echo "=== 1. netlist -> json (yosys) ==="
( cd $ETH && $YOSYS -p "script viv2json.ys" -p "write_json $WORK/arp.json" \
    > $WORK/yosys.log 2>&1 ) || { tail -5 $WORK/yosys.log; exit 1; }
# viv2json.ys already ends in write_json /tmp/vivado_arp.json; prefer our copy
[ -s $WORK/arp.json ] || cp /tmp/vivado_arp.json $WORK/arp.json

echo "=== 2. floorplan (prjxray tilegrid) ==="
PRJXRAY_TILEGRID=$PXDB/xc7vx485t/tilegrid.json \
  python3 $SVS/xilinx_lef/gen_floorplan.py $WORK/floorplan.json > $WORK/floorplan.log 2>&1

echo "=== 3. SVS place ==="
( cd $SVS && \
  TOPO_SITE_PHYSMAP=$SVS/xilinx_lef/xc7vx485t_bram_physmap.txt \
  TOPO_COH_W=10 TOPO_SITE_W=300 TOPO_SITE_FRAC=0.55 TOPO_REGION_FILL=0.5 TOPO_SA_MOVES=900000 \
  TOPO_CONG_W=6 TOPO_CONG_CAP=8 TOPO_CONG_BIN=5 TOPO_LL_W=8 TOPO_LL_HCAP=5 TOPO_LL_VCAP=5 \
  TOPO_FEEDTHRU=18 TOPO_RELAY_MAXD=6 TOPO_BUF_TYPE=BUFR TOPO_BUFR_PER_REGION=0 \
  TOPO_BUFG_FANOUT=24 TOPO_BUFG_MAX=40 \
  TOPO_FIXNETS=$WORK/fixnets.txt TOPO_PLACE=sa TOPO_SEED=1 \
  BELS_OUT=$WORK/bels.txt TOPO_FT_JSON=$WORK/arp_ft.json \
  TOPO_STAMPED_JSON=$WORK/arp_stamped_ocaml.json PLACED_OUT=$WORK/placed.txt \
  $SVS/_build/default/place_lef.exe $WORK/floorplan.json $WORK/arp.json \
  2>&1 | grep -E "FOM:|feedthroughs|carry-stamp" ) ; : > $WORK/fixnets.txt

echo "=== 4. carry-slice completion ==="
CARRY_FLOORPLAN=$WORK/floorplan.json \
  python3 $SVS/carry_stamp.py $WORK/arp_ft.json $WORK/bels.txt $WORK/arp_stamped.json

echo "=== 5. route (nextpnr router2) ==="
$LOCK env NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 NEXTPNR_SKIP_FAILED_ARCS=1 NEXTPNR_ARC_MAX_VISIT=400000 \
  $NEXTPNR --router router2 --chipdb $CHIPDB --xdc $ETH/r0_pins.xdc \
  --json $WORK/arp_stamped.json --fasm $WORK/arp.fasm > $WORK/route.log 2>&1 || true
SK=$(grep -ac SKIP_FAILED_ARCS $WORK/route.log || true)
echo "SKIPS=$SK"
[ "$SK" = 0 ] || { echo "ROUTE INCOMPLETE"; grep -a SKIP_FAILED_ARCS $WORK/route.log | head -5; exit 1; }
grep -a "ERROR" $WORK/route.log | head -3 || true

echo "=== 6. bitstream (prjxray) ==="
GTCOMMON=$(grep -oE "GTX_COMMON_X[0-9]+Y[0-9]+" $WORK/arp.fasm | head -1)
[ -n "$GTCOMMON" ] && printf '%s.IBUFDS_GTE2_Y0.CLKCM_CFG\n%s.IBUFDS_GTE2_Y0.CLKRCV_TRST\n' \
  "$GTCOMMON" "$GTCOMMON" >> $WORK/arp.fasm
PXPY=$PRJXRAY/env/bin/python; [ -x "$PXPY" ] || PXPY=python3
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $PRJXRAY/utils/fasm2frames.py \
  --db-root $PXDB --part $PART $WORK/arp.fasm $WORK/arp.frames > $WORK/f2f.log 2>&1 \
  || { echo F2F FAILED; tail -5 $WORK/f2f.log; exit 1; }
$PRJXRAY/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file $WORK/arp.frames --output_file $OUT > $WORK/f2b.log 2>&1 \
  || { echo F2B FAILED; tail -5 $WORK/f2b.log; exit 1; }
ls -l $OUT | awk '{print "SVS_ARP BIT:",$5,"bytes ->",$9}'
echo "SVS_ARP_DONE"
