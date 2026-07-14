#!/usr/bin/env python3
"""Correlate Vivado report_timing (-input_pins, setup) against the OpenTimer
harness output, joined by ENDPOINT pin.  Compares DATA-PATH DELAY (launch
clock pin -> endpoint arrival), NEVER slack (period conventions differ).

Vivado side : per-path Data Path Delay + logic/route split (worst per endpoint)
OpenTimer   : per-pin LATE arrival from dump_at (<pfx>.at) minus the median
              clock-pin arrival (uniform clock lump), giving cq+logic+route —
              the same quantity as Vivado's Data Path Delay.  The OT path
              report (<pfx>.ot.rpt) additionally provides logic/route splits
              for the endpoints it covers.

usage: correlate_vivado.py <vivado_setup.txt> <pfx>   (expects <pfx>.at,
       <pfx>.ot.rpt, <pfx>.conn in the cwd)
"""
import sys, re, statistics, os

viv_file, pfx = sys.argv[1], sys.argv[2]

def canon(name):
    return "_".join(re.findall(r"[A-Za-z0-9]+", name))

CLKPINS = ("C", "CK", "CLK", "CLKARDCLK", "CLKBWRCLK", "WCLK",
           "CLKARDCLKL", "CLKARDCLKU", "CLKBWRCLKL", "CLKBWRCLKU")

# ---------------- Vivado setup report ----------------
viv = {}
cur = {}
def flush(cur):
    if cur.get("ep") and "dpd" in cur:
        k = cur["ep"]
        if k not in viv or cur["dpd"] > viv[k]["dpd"]:
            viv[k] = cur
for ln in open(viv_file, errors="replace"):
    s = ln.strip()
    if s.startswith("Slack"):
        flush(cur)
        cur = {}
    elif s.startswith("Source:"):
        cur["src"] = s.split(None, 1)[1]
    elif s.startswith("Destination:"):
        cur["dst"] = s.split(None, 1)[1]
        cur["ep"] = canon(cur["dst"])
    elif s.startswith("Data Path Delay:"):
        m = re.search(r"Data Path Delay:\s*(-?[\d.]+)ns\s*\(logic\s*([\d.]+)ns.*route\s*([\d.]+)ns", s)
        if m:
            cur["dpd"] = float(m.group(1))
            cur["logic"] = float(m.group(2))
            cur["route"] = float(m.group(3))
flush(cur)

# ---------------- OpenTimer per-pin late arrivals ----------------
ot_at = {}          # canon(pin) -> late arrival (max of L/R, L/F)
ck_ats = []
for i, ln in enumerate(open(pfx + ".at", errors="replace")):
    f = ln.split()
    if len(f) < 5 or f[0] in ("At", "-", "E/R"):
        continue
    try:
        lr, lf = float(f[2]), float(f[3])
    except ValueError:
        continue
    pin = f[4]
    late = max(lr, lf)
    ot_at[canon(pin)] = late
    if ":" in pin and pin.rsplit(":", 1)[-1] in CLKPINS:
        ck_ats.append(late)
ck_off = statistics.median(ck_ats) if ck_ats else 0.0

# ---------------- OpenTimer path report: logic/route splits ----------------
drivers = set()
for ln in open(pfx + ".conn"):
    p = ln.rstrip("\n").split("\t")
    if len(p) >= 2 and not p[1].startswith("PORT:"):
        drivers.add(p[1])
ot_split = {}       # canon(endpoint) -> (logic, route)
blk = None
if os.path.exists(pfx + ".ot.rpt"):
    for ln in open(pfx + ".ot.rpt", errors="replace"):
        st = ln.strip()
        if st.startswith("Startpoint"):
            blk = {"rows": []}
        elif blk is None:
            continue
        elif st.startswith("Endpoint"):
            blk["ep"] = st.split(":", 1)[1].strip()
        elif st.startswith("Analysis type"):
            blk["el"] = st.split(":", 1)[1].strip()
        elif st.startswith(("pin ", "port ")):
            f = st.split()
            try:
                d = float(f[1])
            except (ValueError, IndexError):
                continue
            pintok = None
            for tok in f[3:]:
                if ":" in tok:
                    pintok = tok
            blk["rows"].append((d, pintok))
        elif st.startswith("slack"):
            if blk.get("el") == "max" and blk.get("ep"):
                logic = route = 0.0
                for d, pintok in blk["rows"][1:]:
                    if pintok is not None and pintok in drivers:
                        logic += d
                    else:
                        route += d
                ot_split.setdefault(canon(blk["ep"]), (logic, route))
            blk = None

# ---------------- join ----------------
def ot_candidates(dst):
    """Vivado 'cell/PIN' -> candidate OT canon keys.  nextpnr's repack
    renames pins: RAMB buses split into L/U halves (ADDRARDADDR[11] ->
    ADDRARDADDRL11/ADDRARDADDRU11), FF set/reset pins fold into SR, C->CK."""
    cands = [canon(dst)]
    m = re.match(r"(.*)/([A-Za-z_]+)(?:\[(\d+)\])?$", dst)
    if not m:
        return cands
    cell, pin, idx = m.groups()
    ck = canon(cell)
    if idx is not None:
        for suf in ("L", "U"):
            cands.append(f"{ck}_{pin}{suf}{idx}")
        cands.append(f"{ck}_{pin}{idx}")
    else:
        alias = {"S": "SR", "R": "SR", "PRE": "SR", "CLR": "SR", "C": "CK"}
        if pin in alias:
            cands.append(f"{ck}_{alias[pin]}")
    return cands

pairs = []
for k, v in viv.items():
    hit = None
    for c in ot_candidates(v["dst"]):
        if c in ot_at:
            hit = c
            break
    if hit is not None:
        pairs.append((hit, v, ot_at[hit] - ck_off))

print(f"vivado endpoints: {len(viv)}   OT valued pins: {len(ot_at)}   "
      f"matched endpoints: {len(pairs)}   (OT clock-pin offset {ck_off:.3f} ns)")
if len(pairs) < 3:
    for k, v, _ in list(viv.items())[:5]:
        print("unmatched viv ep:", k)
    sys.exit(0)

xs = [v["dpd"] for _, v, _ in pairs]
ys = [y for _, _, y in pairs]
ratios = [y / x for x, y in zip(xs, ys) if x > 0.05]
n = len(xs)
mx, my = sum(xs) / n, sum(ys) / n
sxx = sum((x - mx) ** 2 for x in xs)
syy = sum((y - my) ** 2 for y in ys)
sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
r2 = (sxy * sxy) / (sxx * syy) if sxx > 0 and syy > 0 else float("nan")
slope = sxy / sxx if sxx > 0 else float("nan")
icept = my - slope * mx

print("data-path delay, OT vs Vivado (ns):")
print(f"  N                 : {n}")
print(f"  mean ratio OT/Viv : {statistics.mean(ratios):.3f}")
print(f"  median ratio      : {statistics.median(ratios):.3f}")
print(f"  fit OT = {slope:.3f}*Viv + {icept:+.3f}    R^2 = {r2:.3f}")
print(f"  Viv range [{min(xs):.2f}, {max(xs):.2f}]   OT range [{min(ys):.2f}, {max(ys):.2f}]")

pairs.sort(key=lambda p: abs(p[2] - p[1]["dpd"]), reverse=True)
print("\nworst 10 mismatches (endpoint, ns):")
print(f"{'endpoint':64s} {'viv':>6s} {'ot':>6s} {'d':>6s}  viv logic/route   ot logic/route")
for k, v, y in pairs[:10]:
    sp = ot_split.get(k)
    sps = f"{sp[0]:5.2f}/{sp[1]:<5.2f}" if sp else "   (not in rpt)"
    print(f"{v['dst'][:64]:64s} {v['dpd']:6.2f} {y:6.2f} {y-v['dpd']:6.2f}"
          f"  {v['logic']:5.2f}/{v['route']:<5.2f}     {sps}")
