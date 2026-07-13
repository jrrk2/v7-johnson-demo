#!/bin/bash
# TOPOGRAPHICAL variant of build_r0_arpm.sh.  Same frozen eth_macro (Vivado
# placement + fixed-routes for the GT/PCS/PMA transceiver -- unavoidable hard IP),
# but the USER FABRIC (arp_ctrl/cpu logic, RAMB buffers) is placed by the SVS
# route-length-aware topographical placer instead of nextpnr's SA soup placer.
#
# Prereqs (already produced by the SVS placer run):
#   /tmp/r0_arpm.json          -- the merged yosys netlist (user + macro)
#   /tmp/arpm_user_bels.txt    -- our fabric BEL stamps (SLICE/BRAM), macro-free
# Reuses the EXISTING /tmp/r0_arpm.json (does NOT re-run yosys) so cell names
# match what the placer packed.
set -eu
ROOT=/home/jonathan/v7-johnson-demo
ETH=$ROOT/ethsoc
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2
FABBELS=${FABBELS:-/tmp/arpm_user_bels.txt}

# 1. macro placement + macro-internal fixed routes (identical to build_r0_arpm.sh)
sed 's|^\([^#[:space:]]\)|eth/eth_macro1/\1|' $ETH/eth_macro.routes > /tmp/eth_macro_arpm.routes
sed 's|^u_macro/|eth/eth_macro1/|' $ETH/placement_macro.txt > /tmp/placement_arpm.txt
python3 $ETH/stamp_placement.py /tmp/r0_arpm.json /tmp/placement_arpm.txt \
        /tmp/r0_arpm_topo_stamped.json /tmp/eth_macro_arpm.routes

# 2. ALSO stamp our topographical fabric BELs (only cells that still exist after
#    stamp_placement's pad-buffer stitch / routethru insertion).
python3 - /tmp/r0_arpm_topo_stamped.json "$FABBELS" <<'PY'
import json, sys, collections
j = json.load(open(sys.argv[1]))
tops = [m for m, md in j['modules'].items()
        if md.get('cells') and not md.get('attributes', {}).get('blackbox')]
top = j['modules']['top' if 'top' in j['modules'] else max(tops, key=lambda m: len(j['modules'][m]['cells']))]
cells = top['cells']
n = collections.Counter()
for ln in open(sys.argv[2]):
    if '\t' not in ln: continue
    name, bel = ln.rstrip('\n').split('\t')
    c = cells.get(name)
    if c is None:
        n['missed'] += 1; continue
    if 'BEL' in c.get('attributes', {}):
        n['already'] += 1; continue        # never override a macro stamp
    c.setdefault('attributes', {})['BEL'] = bel
    n['stamped'] += 1
json.dump(j, open(sys.argv[1], 'w'))
print("  fabric stamp:", dict(n))
PY

# 3. nextpnr: honour BOTH stampings (macro + fabric), route, report fmax.
PIP_BLACKLIST=${PIP_BLACKLIST:-$ROOT/ibexsoc/openflow/pip_blacklist_int_r_bounce.txt}
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_EXCLUDE_STAMPED_BBOX=1 \
  NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 NEXTPNR_PIP_BLACKLIST=$PIP_BLACKLIST \
  $NEXTPNR --chipdb $CHIPDB --xdc $ETH/r0_pins.xdc --json /tmp/r0_arpm_topo_stamped.json \
    --fixed-routes /tmp/eth_macro_arpm.routes \
    --fasm /tmp/r0_arpm_topo.fasm --write /tmp/r0_arpm_topo_routed.json \
    --freq 50 --router router2 --placer sa --ignore-loops \
    > /tmp/r0_arpm_topo_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -30 /tmp/r0_arpm_topo_npnr.log; exit 1; }
echo "=== nextpnr result ==="
grep -iE "Max frequency|Routing complete|failed|unrouted|Info: Device" /tmp/r0_arpm_topo_npnr.log | tail -15
echo "R0_ARPM_TOPO_ROUTE_DONE"
