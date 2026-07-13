#!/usr/bin/env python3
"""Compare OPEN (nextpnr) vs GOLDEN (Vivado) per-net routing delays.

Both designs share the SAME stamped placement, so a net's driver+sink PINS sit
at the same sites -- but the ROUTING (pips/wires) differs, so the INTERCONNECT
delay differs.  Each SDF lists (INTERCONNECT driver_pin sink_pin (min:typ:max)).
Names differ (Vivado vs yosys-flattened), so we compare by:
  1. distribution (median/p90/p95) of net delays, overall + per fanout
  2. matched arcs where driver+sink pin names sanitize-match

usage: compare_routing.py <open.sdf> <golden.sdf>
"""
import sys, re, collections, statistics as st

def parse(path):
    txt = open(path).read()
    sc = 0.001 if re.search(r'TIMESCALE\s+[\d.]+\s*ps', txt) else 1.0
    arcs = {}          # (driver,sink) -> delay_ns
    drv = collections.defaultdict(list)
    for m in re.finditer(r'\(INTERCONNECT\s+(\S+)\s+(\S+)\s+\(([^)]*)\)', txt):
        d, s, v = m.group(1), m.group(2), m.group(3)
        nums = re.findall(r'-?\d+\.?\d*', v)
        if not nums: continue
        dl = max(float(x) for x in nums) * sc
        arcs[(d, s)] = dl
        drv[d].append(dl)
    return arcs, drv

def norm(p):   # sanitize a pin name for cross-tool matching
    p = p.replace("\\", "").replace("/", "_").replace(".", "_")
    p = re.sub(r'\[(\d+)\]', r'_\1', p)
    return p.lower()

op, ogd = parse(sys.argv[1]), parse(sys.argv[2])
oarcs, odrv = op
garcs, gdrv = ogd

def dist(drv):
    allv = [x for v in drv.values() for x in v]
    byfo = collections.defaultdict(list)
    for d, v in drv.items(): byfo[len(v)] += v
    return allv, byfo

oa, obf = dist(odrv); ga, gbf = dist(gdrv)
def p(xs, q): xs=sorted(xs); return xs[min(len(xs)-1,int(q*len(xs)))]
print(f"{'':8s}{'nets':>7s}{'arcs':>7s}{'median':>9s}{'p90':>9s}{'p95':>9s}  (net delay, ns)")
print(f"{'OPEN':8s}{len(odrv):7d}{len(oa):7d}{st.median(oa):9.3f}{p(oa,.9):9.3f}{p(oa,.95):9.3f}")
print(f"{'GOLDEN':8s}{len(gdrv):7d}{len(ga):7d}{st.median(ga):9.3f}{p(ga,.9):9.3f}{p(ga,.95):9.3f}")
print(f"{'ratio':8s}{'':7s}{'':7s}{st.median(oa)/st.median(ga):9.2f}{p(oa,.9)/p(ga,.9):9.2f}{p(oa,.95)/p(ga,.95):9.2f}  (open/golden)")
print("\nper-fanout median net delay (ns):  fanout   open  golden  ratio")
for fo in sorted(set(obf)&set(gbf), key=int)[:12]:
    if len(obf[fo])>=3 and len(gbf[fo])>=3:
        print(f"    {fo:28d}{st.median(obf[fo]):7.3f}{st.median(gbf[fo]):7.3f}{st.median(obf[fo])/st.median(gbf[fo]):7.2f}")

# matched arcs by normalized (driver,sink)
gmap = {(norm(d), norm(s)): v for (d, s), v in garcs.items()}
matched = [(v, gmap[(norm(d), norm(s))]) for (d, s), v in oarcs.items()
           if (norm(d), norm(s)) in gmap]
if matched:
    ratios = [o/g for o, g in matched if g > 0]
    print(f"\nMATCHED arcs (same driver->sink pin in both): {len(matched)}")
    print(f"  open/golden delay ratio: median {st.median(ratios):.2f}  "
          f"p90 {p(ratios,.9):.2f}  (>1 => open routing slower)")
    worse = sum(1 for r in ratios if r > 1.1)
    print(f"  {worse}/{len(ratios)} arcs >10% slower in open")
