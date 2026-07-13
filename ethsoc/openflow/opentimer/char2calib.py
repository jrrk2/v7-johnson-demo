#!/usr/bin/env python3
"""Build a load-aware calibration from the per-arc delay CHARACTERISTIC dumped
from the golden Vivado design (extract_char.tcl -> arcs.tsv).

Each row: libcell, arc TYPE, DELAY_SLOW_MAX_RISE (slow corner/late),
DELAY_FAST_MIN_RISE (fast corner/early), fanout (load proxy = pin count on the
output net).  Because the design has thousands of instances of each cell type
at DIFFERENT real loads, the distribution of slow_max captures delay-vs-load --
far more realistic than one write_sdf point.  We emit:
  cq/comb  = p95 of slow_max (worst realistic-load setup delay)
  su/hd    = kept from the SDF calib (constraint values, load-independent)
and a per-type (base, slope) linear fit delay ~ base + slope*fanout (reported).

usage: char2calib.py arcs.tsv [calib.json]   (merges into existing calib.json)
"""
import sys, json, collections, statistics, os

tsv = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "calib.json"

rows = collections.defaultdict(list)   # (libcell, kind) -> [(slowmax, fanout)]
def kind(typ):
    t = typ.lower()
    if "setup" in t: return "su"
    if "hold" in t: return "hd"
    if "edge" in t or "clock" in t or t in ("rising_edge","falling_edge"): return "cq"
    return "comb"

for ln in open(tsv):
    p = ln.rstrip("\n").split("\t")
    if len(p) < 5 or p[0] == "libcell": continue
    lc, typ = p[0], p[1]
    try: smx = float(p[2]); fo = int(p[4] or 0)
    except: continue
    if smx <= 0: continue
    rows[(lc, kind(typ))].append((smx, fo))

def p95(xs):
    xs = sorted(xs);
    return xs[min(len(xs)-1, int(0.95*len(xs)))]
def linfit(pairs):   # delay ~ base + slope*fanout
    if len(pairs) < 3: return (statistics.mean(d for d,_ in pairs), 0.0)
    xs = [f for _,f in pairs]; ys = [d for d,_ in pairs]
    mx, my = statistics.mean(xs), statistics.mean(ys)
    den = sum((x-mx)**2 for x in xs) or 1
    slope = sum((x-mx)*(y-my) for x,y in zip(xs,ys))/den
    return (my - slope*mx, slope)

calib = json.load(open(out)) if os.path.exists(out) else {}
print(f"{'cell/kind':22s} {'n':>5s} {'min':>7s} {'p95':>7s} {'max':>7s}  base+slope*fanout")
per_type = collections.defaultdict(dict)
for (lc, k), pairs in sorted(rows.items()):
    ds = [d for d,_ in pairs]
    base, slope = linfit(pairs)
    print(f"{lc+'/'+k:22s} {len(ds):5d} {min(ds):7.3f} {p95(ds):7.3f} {max(ds):7.3f}  "
          f"{base:.3f}+{slope:.5f}*fo")
    if k in ("cq", "comb"):
        per_type[lc][k] = round(p95(ds), 4)     # worst realistic load
for lc, e in per_type.items():
    calib.setdefault(lc, {}).update(e)
json.dump(calib, open(out, "w"), indent=1)
print(f"\nmerged load-aware cq/comb (p95) into {out} for {len(per_type)} cell types "
      f"(su/hd kept from SDF constraints)")
