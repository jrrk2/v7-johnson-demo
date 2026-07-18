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
# Fresh machines have no ~/prjxray checkout: the deps clone + the extracted
# device-db release (make prjxray-db) ARE the ground truth there.
[ -d "$PRJXRAY/database/virtex7" ] || PRJXRAY=$ROOT/deps/prjxray
PXDB=$PRJXRAY/database/virtex7
[ -d "$PXDB" ] || { echo "no virtex7 DB at $PXDB -- run 'make prjxray-db' first" >&2; exit 1; }
PART=xc7vx485tffg1761-2
NEXTPNR=${NEXTPNR:-$ROOT/deps/nextpnr-xilinx/build-opt/nextpnr-xilinx}
[ -x "$NEXTPNR" ] || NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
WORK=${WORK:-/tmp/svs_arp_build}
OUT=${OUT:-/tmp/svs_arp.bit}
mkdir -p "$WORK"
LOCK="flock /tmp/nextpnr.lock"; command -v flock >/dev/null || LOCK=""

echo "=== 1. netlist json ==="
# SVS_SYNTH=1: synthesize from RTL SOURCE with the SVS pipeline (verible
# parse -> unroll/inline/iflift/blocking_subst/meminfer/memlower/srl_infer
# -> gate_map wrappers + PCS passthrough -> flatten -> nextpnr json).
# Silicon-validated frontend (15-bug campaign, 2026-07-18); the open
# P&R of THIS netlist is fresh territory -- gate on SKIPS=0 + hardware.
if [ -n "${SVS_SYNTH:-}" ]; then
  echo "=== 1s. SVS synthesis (arp_open.lua) ==="
  mkdir -p /tmp/svs_arp_synth_build
  ( cd "$SVS" && MEMLOWER_FPGA=1 FPGA_LEC_NAMES=1 \
      ./_build/default/sv_suite.exe script $ETH/svs_race/arp_open.lua \
      > $WORK/svs_synth.log 2>&1 ) \
    || { echo "SVS SYNTH FAILED:"; tail -8 $WORK/svs_synth.log; exit 1; }
  [ /tmp/svs_arp_synth_build/arp.json -ef $WORK/arp.json ] || cp /tmp/svs_arp_synth_build/arp.json $WORK/arp.json
  grep -aE 'WROTE|gate_map|PASS-THROUGH' $WORK/svs_synth.log | tail -3
else
# CANONICAL INPUT: the exact json the silicon-validated bit was placed and
# routed from (net numbering determines the router's net order; a regenerated
# json routes DIFFERENTLY on the same placement, and nextpnr can land on a
# route whose fasm encoding is broken with zero skipped arcs -- seen live:
# make-built bit dead, 35k-line fasm delta, same placement).  Set
# REGEN_NETLIST=1 to rebuild via yosys instead (then VERIFY via the gate).
if [ -z "${REGEN_NETLIST:-}" ] && [ -s $ETH/vivado_arp.json.gz ]; then
  gunzip -c $ETH/vivado_arp.json.gz > $WORK/arp.json
  echo "using pinned ethsoc/vivado_arp.json.gz"
else
echo "=== 1a. netlist -> json (yosys) ==="
( cd $ETH && $YOSYS -p "script viv2json.ys" -p "write_json $WORK/arp.json" \
    > $WORK/yosys.log 2>&1 ) || { tail -5 $WORK/yosys.log; exit 1; }
[ -s $WORK/arp.json ]

echo "=== 1b. strip GT-pin IBUFs ==="
# Vivado's netlist puts plain IBUFs on the GT analog pins (sgmii_refclk_p/n,
# sgmii_rxp/n).  Those pins are IPADs -- the real input buffer is inside the
# GT macro -- and nextpnr errors binding an IBUF there ("No Bel named
# IPAD_X2Y8/IOB33/INBUF_EN").  Bypass: merge each such IBUF's output net into
# its port net and drop the cell (matches the silicon-validated netlist).
python3 - "$WORK/arp.json" <<'PY'
import json, sys
p = sys.argv[1]
j = json.load(open(p))
mod = max(j["modules"].values(), key=lambda m: len(m.get("cells", {})))
cells, ports = mod["cells"], mod["ports"]
port_bits = {}
for pn, pd in ports.items():
    if pn.startswith("sgmii_"):
        for b in pd.get("bits", []):
            if isinstance(b, int):
                port_bits[b] = pn
drop, remap = [], {}
for cn, c in cells.items():
    if c.get("type") == "IBUF":
        i = c["connections"].get("I", [None])[0]
        o = c["connections"].get("O", [None])[0]
        if isinstance(i, int) and i in port_bits and isinstance(o, int):
            remap[o] = i
            drop.append(cn)
for cn in drop:
    del cells[cn]
def rewrite(bits):
    return [remap.get(b, b) if isinstance(b, int) else b for b in bits]
for c in cells.values():
    for pn2, bl in c.get("connections", {}).items():
        c["connections"][pn2] = rewrite(bl)
for e in mod.get("netnames", {}).values():
    e["bits"] = rewrite(e.get("bits", []))
json.dump(j, open(p, "w"))
print(f"stripped {len(drop)} GT-pin IBUFs: {sorted(drop)}")
PY
fi
fi

echo "=== 2. floorplan (prjxray tilegrid) ==="
PRJXRAY_TILEGRID=$PXDB/xc7vx485t/tilegrid.json \
  python3 $SVS/xilinx_lef/gen_floorplan.py $WORK/floorplan.json > $WORK/floorplan.log 2>&1 \
  || { echo "FLOORPLAN FAILED:"; tail -5 $WORK/floorplan.log; exit 1; }

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
  2>&1 | grep --line-buffered -E "FOM:|feedthroughs|carry-stamp|SA .*moves=|site physmap|mode=" ) ; : > $WORK/fixnets.txt

echo "=== 4. carry-slice completion ==="
CARRY_FLOORPLAN=$WORK/floorplan.json \
  python3 $SVS/carry_stamp.py $WORK/arp_ft.json $WORK/bels.txt $WORK/arp_stamped.json

echo "=== 5. route (nextpnr router2) ==="
# Stream the router's phase/iteration lines (full transcript in route.log);
# a silent 10-20 min route reads as a hang.
$LOCK env NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 NEXTPNR_SKIP_FAILED_ARCS=1 NEXTPNR_ARC_MAX_VISIT=400000 \
  $NEXTPNR --router router2 --chipdb $CHIPDB --xdc $ETH/r0_pins.xdc \
  --json $WORK/arp_stamped.json --fasm $WORK/arp.fasm --write $WORK/arp_routed.json 2>&1 \
  | tee $WORK/route.log \
  | grep --line-buffered -E "Info: (Packing|Placing|Placed|Running|Routing global|routing clock|SLICE|Max frequency)|iter=|ERROR|unbound" \
  || true
SK=$(grep -ac SKIP_FAILED_ARCS $WORK/route.log || true)
echo "SKIPS=$SK"
[ "$SK" = 0 ] || { echo "ROUTE INCOMPLETE"; grep -a SKIP_FAILED_ARCS $WORK/route.log | head -5; exit 1; }
grep -a "ERROR" $WORK/route.log | head -3 || true

echo "=== 6. bitstream (prjxray) ==="
GTCOMMON=$(grep -oE "GTX_COMMON_X[0-9]+Y[0-9]+" $WORK/arp.fasm | head -1)
[ -n "$GTCOMMON" ] && printf '%s.IBUFDS_GTE2_Y0.CLKCM_CFG\n%s.IBUFDS_GTE2_Y0.CLKRCV_TRST\n' \
  "$GTCOMMON" "$GTCOMMON" >> $WORK/arp.fasm
# Use the DEPS prjxray python env: its package resolves tile segbits via the
# ALIAS behaviour the silicon-validated frames were built with.  ~/prjxray's
# env (commit 14eb237 "prefer own segbits over alias") flips bit positions
# for whole tile classes on virtex7 -> 8066 frame words lost, dead datapath.
PXPY=$ROOT/deps/prjxray/env/bin/python
[ -x "$PXPY" ] || PXPY=$PRJXRAY/env/bin/python
[ -x "$PXPY" ] || PXPY=python3
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $PRJXRAY/utils/fasm2frames.py \
  --db-root $PXDB --part $PART $WORK/arp.fasm $WORK/arp.frames > $WORK/f2f.log 2>&1 \
  || { echo F2F FAILED; tail -5 $WORK/f2f.log; exit 1; }
$PRJXRAY/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file $WORK/arp.frames --output_file $OUT > $WORK/f2b.log 2>&1 \
  || { echo F2B FAILED; tail -5 $WORK/f2b.log; exit 1; }
ls -l $OUT | awk '{print "SVS_ARP BIT:",$5,"bytes ->",$9}'
# Compare against the silicon-validated golden checksums.  nextpnr's route is
# float-criticality-driven; other platforms/ISAs may legally produce a
# DIFFERENT zero-skip route -- which is NOT automatically functional (proven:
# an alternate zero-skip route of this same placement was dead on silicon).
GOLD=$ETH/svs_arp.golden.sha256
if [ -f "$GOLD" ]; then
  calc() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | cut -d' ' -f1; }
  gf=$(grep 'arp.frames$' $GOLD | cut -d' ' -f1)
  af=$(calc $WORK/arp.frames)
  if [ "$gf" = "$af" ]; then
    echo "GOLDEN MATCH: frames identical to the silicon-validated build"
  else
    echo "WARNING: frames DIFFER from the silicon-validated golden build."
    echo "         The route diverged on this platform; validate this bit on"
    echo "         hardware (arping) or via the Vivado gate before trusting it."
  fi
fi
echo "SVS_ARP_DONE"
