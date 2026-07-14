#!/usr/bin/env python3
"""Fit the per-class wire-delay constants (calib.json "wire" section) against
Vivado's PER-NET route delays.

Vivado report_timing -input_pins lists, for every path, per-net incremental
delays: 'net (fo=N, routed)  incr  path  netname' followed by the sink pin
line whose FIRST token is the sink SITE.  That per-(net,sink) route delay is
regressed against the wire-class hop counts of the SAME net in the GOLDEN
route (/tmp/cs2_routed.json ROUTING attrs) -- per-net regression, much better
conditioned than per-path.  NB the Vivado reference is Vivado's OWN routing
of the same netlist+placement (/tmp/cs2_viv), not the golden route, so this
is route-approximate by construction.

Join key: driver CELL (net names diverge between yosys/nextpnr and Vivado);
the driver pin line precedes each net line in the report.

usage: fit_wire_model.py <setup.rpt> [hold.rpt ...] <routed.json> <pfx.conn>
       [--write]      (updates calib.json "wire" only with --write)
"""
import sys, os, re, json, collections
import numpy as np
from scipy.optimize import nnls
import route2spef as r2s

HERE = os.path.dirname(os.path.abspath(__file__))

args = [a for a in sys.argv[1:] if a != "--write"]
WRITE = "--write" in sys.argv
rpts, rjson, conn = args[:-2], args[-2], args[-1]

def canon(name):
    return "_".join(re.findall(r"[A-Za-z0-9]+", name))

# ---------------- Vivado reports -> (drivercell, drvpin, sinksite, sinkcell,
#                                      sinkpin, fo, delay) ----------------
netre = re.compile(r"net \(fo=(\d+), routed\)\s+([\d.]+)\s+[\d.]+\s+(\S+)")
recs = []
for rpt in rpts:
    nsep = 0; inpath = False; pend = None; lastpin = None
    for ln in open(rpt, errors="replace"):
        if ln.strip().startswith("Slack ("):
            nsep = 0; inpath = True; pend = None; lastpin = None
            continue
        if not inpath:
            continue
        if re.match(r"^\s*-+\s+-+\s*$", ln) or re.match(r"^\s*-{30,}\s*$", ln):
            nsep += 1
            continue
        if nsep != 2:                      # data path is between sep 2 and 3
            continue
        m = netre.search(ln)
        toks = ln.split()
        if m:
            pend = (m.group(3), int(m.group(1)), float(m.group(2)))
        elif toks and "/" in toks[-1]:
            if pend is not None:           # sink line: SITE ... cell/PIN
                net, fo, d = pend
                sc, sp = toks[-1].rsplit("/", 1)
                recs.append((lastpin, toks[0], sc, sp, fo, d))
                pend = None
            lastpin = toks[-1]             # candidate driver for next net
print(f"[fit] {len(recs)} per-(net,sink) records from {len(rpts)} report(s)")

# ---------------- golden route: driver index + leaf features ----------------
routing, sitemap = r2s.build_netdb(rjson)
drv2net = collections.defaultdict(list)    # canon(cell) -> [(pin, net, fo)]
snk2net = collections.defaultdict(list)    # canon(sinkcell) -> [(pin, net, fo)]
for l in open(conn):
    p = l.rstrip("\n").split("\t")
    if len(p) < 2 or p[1].startswith("PORT:"):
        continue
    cell, pin = p[1].rsplit(":", 1)
    snks = p[2].split() if len(p) > 2 else []
    fo = len(snks)
    drv2net[canon(cell)].append((pin, p[0], fo))
    for s in snks:
        if not s.startswith("PORT:") and ":" in s:
            sc, sp = s.rsplit(":", 1)
            snk2net[canon(sc)].append((sp, p[0], fo))

featcache = {}
def net_feats(net):
    if net not in featcache:
        attr = routing.get(net)
        if not attr:
            featcache[net] = None
        else:
            parent, wires = r2s.parse_routing(attr)
            featcache[net] = r2s.leaf_features(parent, wires) or None
    return featcache[net]

def find_net(drvtok, vfo):
    """Vivado driver pin 'cell/PIN[idx]' -> golden net name (via conn)."""
    if drvtok is None or "/" not in drvtok:
        return None
    cell, pin = drvtok.rsplit("/", 1)
    m = re.match(r"([A-Za-z_]+)(?:\[(\d+)\])?$", pin)
    base, idx = (m.group(1), m.group(2)) if m else (pin, None)
    ents = drv2net.get(canon(cell))
    if not ents:
        return None
    if len(ents) == 1:
        return ents[0][1]
    cands = [base + (idx or "")]
    if idx is not None:
        cands += [f"{base}L{idx}", f"{base}U{idx}"]
    if base == "O":
        cands += ["O6", "O5"]
    if base == "Q":
        cands += ["Q", "MC31"]
    for c in cands:
        for pn, net, fo in ents:
            if pn == c:
                return net
    # fanout tiebreak (L/U halves have split fanout; accept close match)
    best = min(ents, key=lambda e: abs(e[2] - vfo))
    return best[1]

def find_net_by_sink(scell, spin, vfo):
    """fallback when the DRIVER cell was renamed (Vivado _57x_ BUFGs vs
    nextpnr $cebuf$*): the sink cell+pin identifies the net uniquely."""
    ents = snk2net.get(canon(scell))
    if not ents:
        return None
    m = re.match(r"([A-Za-z_]+)(?:\[(\d+)\])?$", spin)
    base, idx = (m.group(1), m.group(2)) if m else (spin, None)
    cands = [base + (idx or "")]
    if idx is not None:
        cands += [f"{base}L{idx}", f"{base}U{idx}"]
    # nextpnr repack pin renames (cf. correlate_vivado.ot_candidates)
    alias = {"S": "SR", "R": "SR", "PRE": "SR", "CLR": "SR", "C": "CK"}
    if base in alias:
        cands.append(alias[base])
    hits = [(pn, net, fo) for pn, net, fo in ents if pn in cands]
    if not hits:
        return None
    return min(hits, key=lambda e: abs(e[2] - vfo))[1]

# ---------------- build regression matrix ----------------
CLASSES = ["single", "double", "quad", "hex", "long", "imux", "bounce",
           "iface", "site", "clk"]
rows, ys, wts, meta = [], [], [], []
miss = collections.Counter()
seen = {}
for drvtok, ssite, scell, spin, fo, d in recs:
    net = find_net(drvtok, fo)
    if net is None:
        net = find_net_by_sink(scell, spin, fo)
        if net is not None:
            miss["driver_via_sink"] += 1
    if net is None:
        miss["driver"] += 1
        continue
    feats = net_feats(net)
    if feats is None:
        miss["noroute"] += 1
        continue
    insite = {l.rsplit("/", 1)[-1]: f for l, f in feats.items()
              if l.startswith(f"SITEWIRE/{ssite}/")}
    m = re.match(r"([A-Za-z_]+)(?:\[(\d+)\])?$", spin)
    base, idx = (m.group(1), m.group(2)) if m else (spin, None)
    cands = [base + (idx or "")]
    if idx is not None:
        cands += [f"{base}L{idx}", f"{base}U{idx}"]
    ft = None
    for c in cands:
        if c in insite:
            ft = insite[c]; miss["sink_exact"] += 1
            break
    if ft is None and insite:               # site max (LUT-letter pins etc.)
        ft = max(insite.values(), key=lambda f: r2s.feat_delay(f, r2s.WIRE_DEFAULT, 0))
        miss["sink_site"] += 1
    if ft is None:
        # site mismatch (e.g. nextpnr's $cebuf$ BUFG on a different BUFGCTRL
        # site than Vivado's _57x_): fall back to the net's worst leaf
        ft = max(feats.values(), key=lambda f: r2s.feat_delay(f, r2s.WIRE_DEFAULT, 0))
        miss["sink_netmax"] += 1
    key = (net, ssite, spin)
    if key in seen:                          # same (net,sink) many paths: max
        if d > ys[seen[key]]:
            ys[seen[key]] = d
        wts[seen[key]] += 1.0                # weight by path occurrence
        continue
    seen[key] = len(ys)
    rows.append([1.0] + [float(ft.get(c, 0)) for c in CLASSES] + [float(fo)])
    ys.append(d)
    wts.append(1.0)
    meta.append((net, ssite, spin, fo))
print(f"[fit] usable records: {len(ys)}   " +
      " ".join(f"{k}={v}" for k, v in sorted(miss.items())))

A = np.array(rows); b = np.array(ys)
# a net on many report paths matters proportionally for the ENDPOINT
# correlation (e.g. the reset->BUFG leg is 1 net on 253/400 endpoints):
# sqrt-of-occurrences row weighting
w = np.sqrt(np.array(wts))
names = ["base"] + CLASSES + ["fanout_per_sink"]
# drop all-zero columns (keep seed value for those)
keep = [i for i in range(A.shape[1]) if A[:, i].any()]
# ridge toward the folklore seeds: the classes are collinear (every path has
# ~1 LOGIC_OUTS + ~1 IMUX + bounce mix), plain nnls zeroes half of them and
# the model goes unphysical off the fitted set.  Augment with sqrt(lam)*I
# rows targeting sqrt(lam)*seed.
lam = float(os.environ.get("FIT_RIDGE", "15.0"))
seed = np.array([r2s.WIRE_DEFAULT[names[i]] for i in keep])
def dofit(Ak, bk, wk):
    Aa = np.vstack([Ak * wk[:, None], np.sqrt(lam) * np.eye(len(keep))])
    ba = np.concatenate([bk * wk, np.sqrt(lam) * seed])
    return nnls(Aa, ba)[0]
x = dofit(A[:, keep], b, w)
# robust pass: the reference is Vivado's OWN routing -- records where its
# route diverges wildly from the golden route (either direction) are not
# model error; trim them and refit so they don't drag the class constants.
trim = float(os.environ.get("FIT_TRIM", "1.5"))
if trim > 0:
    res0 = b - A[:, keep] @ x
    inl = np.abs(res0) < trim
    print(f"[fit] robust pass: trimming {int((~inl).sum())}/{len(b)} records "
          f"with |residual| >= {trim} ns (route divergence)")
    x = dofit(A[np.ix_(inl, keep)], b[inl], w[inl])
W = dict(r2s.WIRE_DEFAULT)
for i, xi in zip(keep, x):
    W[names[i]] = round(float(xi), 4)
pred = A[:, keep] @ x
res = b - pred
ss = 1 - (res @ res) / ((b - b.mean()) @ (b - b.mean()))
print("[fit] class constants (ns):")
for i in keep:
    print(f"   {names[i]:16s} {W[names[i]]:7.4f}   (col mean {A[:, i].mean():6.2f})")
print(f"[fit] residual RMS {np.sqrt((res**2).mean()):.3f} ns   R^2 {ss:.3f}   "
      f"target range [{b.min():.2f},{b.max():.2f}]")
worst = np.argsort(-np.abs(res))[:10]
print("[fit] worst per-net residuals (viv, pred, net -> site/pin):")
for i in worst:
    print(f"   {b[i]:6.2f} {pred[i]:6.2f}  {meta[i][0][:60]} -> {meta[i][1]}/{meta[i][2]} fo={meta[i][3]}")

if WRITE:
    cf = os.path.join(HERE, "calib.json")
    calib = json.load(open(cf)) if os.path.exists(cf) else {}
    calib["wire"] = {k: W[k] for k in names if k in W} | {"clock_lump": W["clock_lump"]}
    json.dump(calib, open(cf, "w"), indent=1)
    print(f"[fit] wrote wire section to {cf}")
