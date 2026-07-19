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
WORK=${WORK:-$ROOT/build/svs_arp}
OUT=${OUT:-$WORK/svs_arp.bit}
mkdir -p "$WORK"
LOCK="flock /tmp/nextpnr.lock"; command -v flock >/dev/null || LOCK=""

# Strip GT analog-pin buffers (IBUF on sgmii_rxp/refclk IPADs, OBUF on
# sgmii_txp/txn OPADs): the real buffers live inside the GT macro, so
# nextpnr errors binding an IO buffer at OPAD/IPAD.  Merge each buffer's
# fabric net into the port net and drop the cell.  Needed for ANY freshly
# generated netlist (SVS synth or yosys); the pinned json is already clean.
#
# NOTE: GT pin DIRECTIONS and WIDTHS are no longer patched here.  SVS now reads
# them from the primitive's Vivado unisim VHDL entity interface (secureip/ for
# the GT macros) via lookup_xil_primitive_ports, so GTXE2 outputs (CPLLLOCK,
# RXOUTCLK, ...) emit as outputs and narrow config pins (LOOPBACK[2:0]) get
# their real width straight out of the emitter.  The emitter now BOMBS on any
# unresolved primitive pin rather than guessing input, so a regression here is
# loud, not a silent false combinatorial loop.

strip_gt_pins() {
python3 - "$1" <<'PY'
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
            remap[o] = i          # IBUF.O -> port net (GT IPAD input pins)
            drop.append(cn)
    elif c.get("type") == "OBUF":
        # GT serial OUTPUT pins (sgmii_txp/txn) are OPADs: the driver is
        # inside the GT macro, so an OBUF binding OPAD_.../OUTBUF errors in
        # nextpnr.  Merge the OBUF INPUT net into the port net and drop it
        # (the GT drives the port directly, matching the Vivado netlist).
        i = c["connections"].get("I", [None])[0]
        o = c["connections"].get("O", [None])[0]
        if isinstance(o, int) and o in port_bits and isinstance(i, int):
            remap[i] = o
            drop.append(cn)
# SVS flatten emits a chain of identity LUT6 pass-through buffers (one per
# hierarchy level) between the GT's GTXTXP/GTXTXN serial output and the
# sgmii_txp/txn ports.  nextpnr then auto-inserts an OBUF on the fabric-driven
# port and binds it to the GT serial OPAD -> "No Bel OPAD/.../OUTBUF".  The
# EDIF emitter's ident-obuf bypass collapses these; the nextpnr-json one does
# not.  Collapse the identity-LUT6 chain here so the GT output drives the port
# directly (nextpnr's constrain_gt then binds GTXTXP->OPAD, no fabric buffer).
def is_ident_lut(c):
    if c.get("type") != "LUT6":
        return False
    init = c.get("parameters", {}).get("INIT", "")
    # identity LUT6: O = I0  (INIT = 0xFFFFFFFF00000000, MSB-first all-1 hi
    # half / all-0 lo half) with every input tied to the same net.
    if init.count("1") != 32 or init.count("0") != 32:
        return False
    ins = [c["connections"].get(f"I{k}", [None])[0] for k in range(6)]
    return len(set(ins)) == 1 and isinstance(ins[0], int)
# net -> the (single) identity-LUT cell that drives it
lut_drv = {}
for cn, c in cells.items():
    if is_ident_lut(c):
        o = c["connections"].get("O", [None])[0]
        if isinstance(o, int):
            lut_drv[o] = cn
lut_dropped = 0
for pn, pd in ports.items():
    if not pn.startswith("sgmii_") or pd.get("direction") != "output":
        continue
    for b in pd.get("bits", []):
        if not isinstance(b, int):
            continue
        # walk the identity-LUT chain from the port bit to its real source
        cur, chain = b, []
        while cur in lut_drv and lut_drv[cur] not in chain:
            cn = lut_drv[cur]
            chain.append(cn)
            cur = cells[cn]["connections"]["I0"][0]
        if chain:
            remap[cur] = b            # GT serial output net -> the port bit
            for cn in chain:
                if cn not in drop:
                    drop.append(cn); lut_dropped += 1
for cn in drop:
    cells.pop(cn, None)
# resolve remap transitively (chains of aliases)
def resolve(x):
    seen = set()
    while x in remap and x not in seen:
        seen.add(x); x = remap[x]
    return x
def rewrite(bits):
    return [resolve(b) if isinstance(b, int) else b for b in bits]
for c in cells.values():
    for pn2, bl in c.get("connections", {}).items():
        c["connections"][pn2] = rewrite(bl)
for e in mod.get("netnames", {}).values():
    e["bits"] = rewrite(e.get("bits", []))
json.dump(j, open(p, "w"))
print(f"stripped {len(drop)-lut_dropped} GT-pin buffers + "
      f"{lut_dropped} GT-serial identity LUTs: {sorted(drop)[:6]}...")
PY
}

echo "=== 1. netlist json ==="
# SVS_SYNTH=1: synthesize from RTL SOURCE with the SVS pipeline (verible
# parse -> unroll/inline/iflift/blocking_subst/meminfer/memlower/srl_infer
# -> gate_map wrappers + PCS passthrough -> flatten -> nextpnr json).
# Silicon-validated frontend (15-bug campaign, 2026-07-18); the open
# P&R of THIS netlist is fresh territory -- gate on SKIPS=0 + hardware.
if [ -n "${SVS_SYNTH:-}" ]; then
  echo "=== 1s. SVS synthesis (arp_open.lua) ==="
  mkdir -p "$WORK"
  # NEXTPNR_JSON_CONST_STRINGS=1: emit constants as yosys-style "0"/"1" bits
  # (-> GLOBAL_LOGIC0/1) rather than $PACKER_GND/VCC nets.  nextpnr's GT packer
  # requires the GT clock-select pins (CPLLREFCLKSEL etc.) be driven by
  # GLOBAL_LOGIC or a clock source; the packer-net form makes it reject them
  # as "driven by IOB18_OUTBUF_DCIEN".
  ( cd "$SVS" && MEMLOWER_FPGA=1 FPGA_LEC_NAMES=1 NEXTPNR_JSON_CONST_STRINGS=1 W="$WORK" \
      ./_build/default/sv_suite.exe script $ETH/svs_race/arp_open.lua \
      > $WORK/svs_synth.log 2>&1 ) \
    || { echo "SVS SYNTH FAILED:"; tail -8 $WORK/svs_synth.log; exit 1; }
  grep -aE 'WROTE|gate_map|PASS-THROUGH' $WORK/svs_synth.log | tail -3
  # No GT-pin post-processing on SVS output: bir_to_nextpnr_json now collapses
  # the GT-serial identity-LUT chain (GTXTXP/GTXTXN -> sgmii_txp/txn) in the
  # emitter (collapse_gt_serial), and SVS emits no IBUF/OBUF on the analog pads.
  # strip_gt_pins is retained below only for the yosys netlist path.
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
strip_gt_pins "$WORK/arp.json"
fi
fi

# never reached (structural placeholder for the old inline block below)

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
  TOPO_CARRY_SPREAD=${SVS_SYNTH:+1} TOPO_CARRY_MAX_PER_COL=${TOPO_CARRY_MAX_PER_COL:-32} \
  TOPO_FIXNETS=$WORK/fixnets.txt TOPO_PLACE=sa TOPO_SEED=1 \
  BELS_OUT=$WORK/bels.txt TOPO_FT_JSON=$WORK/arp_ft.json \
  TOPO_STAMPED_JSON=$WORK/arp_stamped_ocaml.json PLACED_OUT=$WORK/placed.txt \
  $SVS/_build/default/place_lef.exe $WORK/floorplan.json $WORK/arp.json \
  2>&1 | grep --line-buffered -E "FOM:|feedthroughs|carry-stamp|SA .*moves=|site physmap|mode=" ) ; : > $WORK/fixnets.txt

echo "=== 4. carry-slice completion ==="
CARRY_FLOORPLAN=$WORK/floorplan.json CARRY_STAMP_AVOID_CI=${SVS_SYNTH:+1} \
  python3 $SVS/carry_stamp.py $WORK/arp_ft.json $WORK/bels.txt $WORK/arp_stamped.json

echo "=== 5. route (nextpnr router2) ==="
# Stream the router's phase/iteration lines (full transcript in route.log);
# a silent 10-20 min route reads as a hang.
# NEXTPNR_PIP_BLACKLIST_TILE: reserve individual INT pips whose prjxray segbit
# collides with a silicon-validated IOB config bit in the shared IO/INT frame
# column (a long-line mis-encoding; see the file + pip_blacklist_int_r_bounce).
# --freq 125: the derived eth clocks (userclk2/rxuserclk = 125 MHz) have
# synthesis-anonymous net names, so they can't be create_clock'd stably; a global
# 125 MHz target makes the router timing-driven on the critical eth domain and
# harmlessly over-constrains cpu_clk (50 MHz).  Default (12 MHz) hid a ~27 MHz
# datapath.  from-source only (${SVS_SYNTH:+}) so the pinned golden is unchanged.
$LOCK env NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 NEXTPNR_SKIP_FAILED_ARCS=1 NEXTPNR_ARC_MAX_VISIT=400000 \
  NEXTPNR_PIP_BLACKLIST_TILE=$ETH/openflow/pip_blacklist_tile.txt \
  $NEXTPNR --router router2 --chipdb $CHIPDB --xdc $ETH/r0_pins.xdc ${SVS_SYNTH:+--freq 125} \
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
