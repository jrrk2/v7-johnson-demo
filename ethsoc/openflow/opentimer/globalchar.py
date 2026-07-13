#!/usr/bin/env python3
"""Extract the GLOBAL clock-network insertion characteristic from the golden
Vivado SDF, to calibrate nextpnr's hardcoded global-pip delays (arch.h
getPipDelay).  Companion to netchar.py -- but netchar models GENERAL signal
routing, which is the wrong population for the dedicated low-skew clock spine.

nextpnr routes a global clock BUFG->sink through the dedicated network; every
such pip hits the global branch of getPipDelay and currently gets a flat 100 ps
(global->global spine) or 250 ps (global->local exit tap), NO RC term.  A V7
BUFG->leaf path = a few dedicated spine hops (CLK_BUFG_REBUF/CLK_HROW/HCLK,
shared) + exactly ONE leaf tap into the sink's fabric tile.  The DCP pip-tile
histogram of the 994-fanout userclk2/eth_clk net confirms ~39 dedicated spine
pips (shared) vs ~993 fabric leaf taps (~1/sink).

The golden SDF gives the whole BUFG->sink delay as one INTERCONNECT number per
sink.  We take the high-fanout (>=100) BUFG-driven nets = the true clock spine
(tight, low-skew: median ~2.05 ns, p95 ~2.09 ns) and emit globalchar.json.

Calibration model (robust to spine hop-count N, which the SDF can't resolve
per-pip): put the dominant, once-per-path delay on the EXIT tap and keep spine
hops small & physical:
    insertion(BUFG->sink) = EXIT + N_spine * SPINE  ~= golden median
    SPINE = 70 ps  (dedicated low-R clock metal, ~ the old 100)
    EXIT  = golden_median - N_spine*SPINE   (N_spine ~= 5 typical)

usage: globalchar.py <golden.sdf> [globalchar.json]
"""
import sys, re, json, collections, statistics as st

sdf = open(sys.argv[1]).read()
out = sys.argv[2] if len(sys.argv) > 2 else "globalchar.json"
sc = 0.001 if re.search(r'TIMESCALE\s+[\d.]+\s*ps', sdf) else 1.0

drv = collections.defaultdict(list)
for m in re.finditer(r'\(INTERCONNECT\s+(\S+)\s+(\S+)\s+\(([^)]*)\)', sdf):
    nums = re.findall(r'-?\d+\.?\d*', m.group(3))
    if nums:
        drv[m.group(1)].append(max(float(x) for x in nums) * sc)

# clock spine = high-fanout global nets (BUFG-driven); tight distribution
clk = [x for d, v in drv.items() if len(v) >= 100 for x in v]
# keep only the tightly-clustered global-network population (drop high-fanout
# SIGNAL nets on general routing: they have a much wider spread).  A global-net
# sink delay sits within +/-15% of the median; signal nets scatter far below.
med0 = st.median(clk)
spine = [x for x in clk if 0.7 * med0 <= x <= 1.3 * med0]

med = st.median(spine)
p95 = sorted(spine)[int(0.95 * len(spine))]
N_SPINE = 5          # typical dedicated spine hops per BUFG->leaf path
SPINE_PS = 70        # per dedicated spine hop (low-R clock metal)
insertion_ps = round(med * 1000)
exit_ps = insertion_ps - N_SPINE * SPINE_PS

json.dump({
    "insertion_ns_median": round(med, 4),
    "insertion_ns_p95": round(p95, 4),
    "n_global_sinks": len(spine),
    "model": {"n_spine": N_SPINE, "spine_ps": SPINE_PS, "exit_ps": exit_ps},
    "note": "BUFG->sink = exit_ps + n_spine*spine_ps ~= insertion_ns_median*1000",
}, open(out, "w"), indent=1)

print(f"global-clock sinks: {len(spine)} (of {len(clk)} high-fanout)")
print(f"  BUFG->sink insertion: median {med*1000:.0f} ps  p95 {p95*1000:.0f} ps")
print(f"  -> arch.h globals: GLOBAL_SPINE_HOP={SPINE_PS} ps, "
      f"GLOBAL_EXIT_HOP={exit_ps} ps  (total ~= {exit_ps+N_SPINE*SPINE_PS} ps)")
print(f"wrote {out}")
