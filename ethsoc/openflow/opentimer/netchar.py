#!/usr/bin/env python3
"""Extract a routing-delay-vs-fanout characteristic from the golden Vivado SDF
INTERCONNECT (net) delays, for calibrating route2spef on the OPEN design.

Golden SDF INTERCONNECT: one (driver/pin sink/pin (min:typ:max)) per net arc.
Group by driver -> fanout = #sinks, per-sink delay.  Emit netchar.json:
  {"byfanout": {fanout: p95_delay_ns}, "fit": [base, slope]}  (delay ~ base+slope*fanout)

The open design's per-net fanout is known (route2spef reads it from .conn), so
each open net gets a Vivado-calibrated routing delay for its fanout -- far more
realistic than a flat per-hop constant.  (Golden routing quality; the open
nextpnr routing may be worse, so this is a calibrated LOWER bound.)

usage: netchar.py <golden.sdf> [netchar.json]
"""
import sys, re, json, collections, statistics

sdf = open(sys.argv[1]).read()
out = sys.argv[2] if len(sys.argv) > 2 else "netchar.json"
mts = re.search(r'\(TIMESCALE\s+[\d.]+\s*(ps|ns)', sdf)
scale = 0.001 if (mts and mts.group(1) == "ps") else 1.0

drv = collections.defaultdict(list)   # driver-pin -> [delay_ns, ...]
for m in re.finditer(r'\(INTERCONNECT\s+(\S+)\s+(\S+)\s+\(([^)]*)\)', sdf):
    d, s, val = m.group(1), m.group(2), m.group(3)
    nums = re.findall(r'-?\d+\.?\d*', val)
    if not nums: continue
    dl = max(float(x) for x in nums) * scale
    drv[d].append(dl)

byfo = collections.defaultdict(list)   # fanout -> [delays]
for d, dls in drv.items():
    fo = len(dls)
    for x in dls: byfo[fo].append(x)

def p95(xs): xs=sorted(xs); return xs[min(len(xs)-1,int(0.95*len(xs)))]
char = {str(fo): round(p95(xs), 4) for fo, xs in byfo.items() if len(xs) >= 3}

# linear fit delay ~ base + slope*fanout over all sinks
xs = [len(dls) for d, dls in drv.items() for _ in dls]
ys = [x for d, dls in drv.items() for x in dls]
mx, my = statistics.mean(xs), statistics.mean(ys)
den = sum((x-mx)**2 for x in xs) or 1
slope = sum((x-mx)*(y-my) for x, y in zip(xs, ys))/den
base = my - slope*mx
json.dump({"byfanout": char, "fit": [round(base,4), round(slope,5)],
           "p50_all": round(statistics.median(ys),4),
           "p95_all": round(p95(ys),4)}, open(out, "w"), indent=1)
print(f"golden net delays: {len(ys)} arcs over {len(drv)} nets")
print(f"  median {statistics.median(ys)*1000:.0f}ps  p95 {p95(ys)*1000:.0f}ps  "
      f"fit delay(ns) ~ {base:.4f} + {slope:.5f}*fanout")
for fo in sorted(byfo, key=int)[:12]:
    if len(byfo[fo])>=3: print(f"    fanout {fo:3d}: p95 {p95(byfo[fo])*1000:6.0f} ps  (n={len(byfo[fo])})")
print(f"wrote {out}")
