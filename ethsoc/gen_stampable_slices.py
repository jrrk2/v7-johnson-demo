#!/usr/bin/env python3
# Emit the list of CLB slices to wholesale-stamp from golden: every slice that
# carries golden config EXCEPT slices holding a fresh (non-eth) cell in the open
# placement.  Covers pure-eth slices AND Vivado route-through LUT slices (which
# carry golden config but appear as no primitive), while protecting mixed slices.
#   usage: gen_stampable_slices.py routed.json gold_b2f.fasm tilegrid.json out.txt
import json, sys, re
routed, goldfasm, tilegrid, out = sys.argv[1:5]

gold_slices = set()
for l in open(goldfasm):
    l = l.strip()
    if l.startswith("CLBL"):
        parts = l.split(".")
        if len(parts) >= 2:
            gold_slices.add(".".join(parts[:2]))

tg = json.load(open(tilegrid))
slice2feat = {}
for t, i in tg.items():
    ss = [s for s in i.get("sites", {}) if s.startswith("SLICE_")]
    for idx, s in enumerate(sorted(ss, key=lambda s: int(re.search(r"X(\d+)", s).group(1)))):
        styp = "SLICEM" if ("CLBLM" in t and idx == 0) else "SLICEL"
        slice2feat[s] = "%s.%s_X%d" % (t, styp, idx)

cells = json.load(open(routed))["modules"]["top"]["cells"]
fresh = set()
for n, c in cells.items():
    if n.startswith("eth"):
        continue
    m = re.search(r"(SLICE_X\d+Y\d+)/", c.get("attributes", {}).get("NEXTPNR_BEL", ""))
    if m and m.group(1) in slice2feat:
        fresh.add(slice2feat[m.group(1)])

stampable = sorted(gold_slices - fresh)
open(out, "w").write("\n".join(stampable) + "\n")
print("gen_stampable_slices: %d golden slices, %d fresh-protected, %d stampable"
      % (len(gold_slices), len(fresh), len(stampable)))
