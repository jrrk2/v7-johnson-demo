#!/usr/bin/env python3
"""Calibrate the OpenTimer cell models from Vivado's back-annotated SDF of the
GOLDEN routed design (write_sdf on the DCP).  Extracts per-cell-type worst-case
arc delays -- clk->Q (IOPATH C/CLK->Q), setup/hold (TIMINGCHECK), and comb
(IOPATH in->out) -- and writes calib.json which json2ot.py applies over its
prjxray-SDF defaults.  This makes the cells "modelled by conversion from the
golden Vivado database".

usage: sdf_calibrate.py <golden.sdf> [calib.json]
"""
import sys, re, collections

sdf = open(sys.argv[1]).read()
out = sys.argv[2] if len(sys.argv) > 2 else "calib.json"
mts = re.search(r'\(TIMESCALE\s+([\d.]+)\s*(ps|ns)', sdf)
PS2NS = 0.001 if (mts and mts.group(2) == "ps") else 1.0   # convert to ns

# instance cell types in the SDF use the Vivado library cell name; map the
# instance CELLTYPE to our netlist type family.
def fam(ct):
    ct = ct.upper()
    if ct.startswith("LUT"): return "LUT"
    if ct.startswith("FD"): return "FD"
    if ct.startswith(("RAMB","FIFO")): return "RAMB"
    if ct.startswith("SRL"): return "SRL"
    if ct == "CARRY4": return "CARRY4"
    if ct.startswith(("RAMD","RAMS","DMEM")): return "RAMD"
    if ct in ("BUFG","BUFGCTRL","BUFH"): return "BUFG"
    return None

# per-family accumulate max delays
cq = collections.defaultdict(float)
su = collections.defaultdict(float)
hd = collections.defaultdict(float)
comb = collections.defaultdict(float)

def maxpair(s):
    # "(a::b)(c::d)" -> max of all numbers, converted to ns
    nums = re.findall(r'-?\d+\.?\d*', s)
    return (max(float(x) for x in nums) * PS2NS) if nums else 0.0

for m in re.finditer(r'\(CELL\s+\(CELLTYPE "([^"]+)"\)(.*?)(?=\(CELL |\Z)', sdf, re.S):
    ct, body = m.group(1), m.group(2)
    f = fam(ct)
    if not f: continue
    for io in re.finditer(r'\(IOPATH\s+(\S+)\s+(\S+)\s+(\([^)]*\)(?:\s*\([^)]*\))?)', body):
        ip, op, val = io.group(1), io.group(2), io.group(3)
        dv = maxpair(val)
        if ip in ("C", "CLK", "CLKARDCLK", "CLKBWRCLK") and op.startswith(("Q", "O", "DO")):
            cq[f] = max(cq[f], dv)
        else:
            comb[f] = max(comb[f], dv)
    # separate SETUP/HOLD ...
    for s in re.finditer(r'\((SETUP|HOLD)\s+\([^)]*\)\s+\([^)]*\)\s+(\([^)]*\))', body):
        dv = maxpair(s.group(2))
        tgt = su if s.group(1) == "SETUP" else hd
        tgt[f] = max(tgt[f], dv)
    # ... or combined SETUPHOLD (data)(clk) (setup) (hold), only D-pin arcs
    for s in re.finditer(r'\(SETUPHOLD\s+\((?:pos|neg)edge\s+(\w+)\)\s+\([^)]*\)\s+(\([^)]*\))\s+(\([^)]*\))', body):
        pin = s.group(1)
        if pin.startswith(("D", "ADDR", "DI")):     # real data/addr setup, skip CE/S/R
            su[f] = max(su[f], abs(maxpair(s.group(2))))
            hd[f] = max(hd[f], abs(maxpair(s.group(3))))

# emit calib for our netlist cell types
TYPES = {"LUT1":"LUT","LUT2":"LUT","LUT3":"LUT","LUT4":"LUT","LUT5":"LUT","LUT6":"LUT",
         "FDRE":"FD","FDSE":"FD","FDPE":"FD","FDCE":"FD","CARRY4":"CARRY4",
         "RAMB36E1":"RAMB","RAMB18E1":"RAMB","SRL16E":"SRL","SRLC32E":"SRL",
         "RAMD64E":"RAMD","RAMD32":"RAMD","RAMS32":"RAMD","BUFG":"BUFG"}
import json
calib = {}
for t, f in TYPES.items():
    e = {}
    if cq[f] > 0: e["cq"] = round(cq[f], 4)
    if su[f] > 0: e["su"] = round(su[f], 4)
    if hd[f] > 0: e["hd"] = round(hd[f], 4)
    if comb[f] > 0: e["comb"] = round(comb[f], 4)
    if e: calib[t] = e
json.dump(calib, open(out, "w"), indent=1)
print(f"wrote {out}: calibrated {len(calib)} cell types")
for f in ("LUT","FD","CARRY4","RAMB","SRL","RAMD","BUFG"):
    print(f"  {f:7s} cq={cq[f]:.3f} su={su[f]:.3f} hd={hd[f]:.3f} comb={comb[f]:.3f}")
