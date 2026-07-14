#!/usr/bin/env python3
"""Emit a proper OpenTimer SPEF from the netlist connectivity (<pref>.conn),
assigning each net PER-SINK interconnect delays.  Elmore delay driver->sink =
R_i * C_sink (star topology, one R per sink); we pick R_i so R_i*C = the
modelled routing delay to THAT sink.

Delay model (per-net Elmore, calib.json "wire" section):
  the routed json's per-net ROUTING attribute (semicolon triples
  wire;pip;strength) gives the actual route tree of the GOLDEN route.  Each
  root->leaf path is a sequence of INT wires; classify each hop (single/
  double/quad/hex/long/imux/bounce/iface/site) and sum per-class delay
  constants + a per-net fanout term.  Consecutive same-name long-line entries
  are ONE physical node (nextpnr ladders LV/LVB/LH once per tile crossed) and
  are counted once.  Constants are FITTED against Vivado per-net route delays
  (fit_wire_model.py).

Fallback (no routed json / no "wire" calib): flat design-wide fanout lump as
before.  Units: NS / PF / KOHM (R*C in kohm*pf = ns).

usage: route2spef.py <fasm> <pref.conn> <out.spef> [routed.json]
"""
import sys, os, json, re, collections

C = 0.001
CPIN = 0.001   # liberty input-pin capacitance (json2ot emits 0.001 pf): OT adds
               # it to the SPEF node cap, so Elmore delay = R*(C+CPIN) -- divide
               # by BOTH or every net delay comes out exactly 2x the model.
HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- wire model
# keep in sync with json2ot.py
def sanitize(s):
    return s.replace("$","_").replace(".","_").replace(":","_").replace("[","_").replace("]","").replace("\\","").replace("/","_")

WIRE_DEFAULT = {           # 7-series folklore seeds (ns); overridden by fit
    "base":   0.045,       # per-net fixed (driver stub, LOGIC_OUTS, ...)
    "single": 0.170,
    "double": 0.210,
    "quad":   0.300,
    "hex":    0.380,
    "long":   0.650,
    "imux":   0.100,
    "bounce": 0.190,       # BYP/FAN bounce + CTRL/GFAN hops
    "iface":  0.070,       # tile<->site interface wires (CLBLM_*, BRAM_*)
    "site":   0.000,       # intra-site SITEWIRE hops
    "clk":    0.100,       # GCLK/HCLK spine hops on NON-clock nets (BUFG resets)
    "fanout_per_sink": 0.008,
    "clock_lump": 0.050,   # dedicated global tree, NOT fabric routing
}

_re_single = re.compile(r"^[NESW][RL]1")
_re_double = re.compile(r"^(NN|SS|EE|WW|NE|NW|SE|SW)2")
_re_quad   = re.compile(r"^(NN|SS|EE|WW)4")
_re_hex    = re.compile(r"^(NN|SS|EE|WW|NE|NW|SE|SW)6")
_re_long   = re.compile(r"^(LH|LV|LVB)(_L)?\d")
_re_clk    = re.compile(r"(^|_)(CLK|GCLK|HCLK)")

def classify(wire):
    """wire = 'TILE/NAME' or 'SITEWIRE/SITE/NAME' -> model class (or None)."""
    if wire.startswith("SITEWIRE/"):
        return "site"
    name = wire.split("/", 1)[1] if "/" in wire else wire
    if name in ("VCC_WIRE", "GND_WIRE"):
        return None
    if _re_single.match(name): return "single"
    if _re_double.match(name): return "double"
    if _re_quad.match(name):   return "quad"
    if _re_hex.match(name):    return "hex"
    if _re_long.match(name):   return "long"
    if name.startswith(("IMUX",)): return "imux"
    if name.startswith(("BYP", "FAN", "GFAN", "CTRL")): return "bounce"
    if _re_clk.search(name):   return "clk"      # global-tree hop (clock nets)
    return "iface"   # LOGIC_OUTS*, CLBLM_*, BRAM_*, INT_INTERFACE_*, ...

def localname(wire):
    return wire.rsplit("/", 1)[-1]

def parse_routing(attr):
    """ROUTING attr -> (parent{wire->srcwire}, wires set).  Triples are
    wire;pip;strength with pip 'SRC->DST' (DST == wire) or empty for roots."""
    p = attr.strip().split(";")
    parent, wires = {}, set()
    for i in range(0, len(p) - 2, 3):
        w, pip = p[i].strip(), p[i + 1].strip()
        if not w:
            continue
        wires.add(w)
        if pip and "->" in pip:
            src = pip.split("->", 1)[0]
            parent.setdefault(w, src)
            wires.add(src)
    return parent, wires

def leaf_features(parent, wires):
    """-> {leafwire: Counter(class->hops)} for every tree leaf.  Walk each
    leaf to its root; consecutive same-name long entries collapse to one."""
    srcs = set(parent.values())
    leaves = [w for w in wires if w not in srcs and w in parent]
    out = {}
    for leaf in leaves:
        feat = collections.Counter()
        w = leaf
        seen = set()
        while w is not None and w not in seen:
            seen.add(w)
            up = parent.get(w)
            cl = classify(w)
            if cl is not None:
                if (cl == "long" and up is not None and classify(up) == "long"
                        and localname(up) == localname(w)):
                    pass          # ladder continuation of the same LV/LH node
                else:
                    feat[cl] += 1
            w = up
        out[leaf] = feat
    return out

def feat_delay(feat, W, fo):
    """clock NETS (majority-CK sinks) never get here (clock_lump); 'clk'-class
    hops here are GCLK spine wires on BUFG-driven reset/CE nets."""
    d = W["base"] + fo * W["fanout_per_sink"]
    for cl, n in feat.items():
        d += n * W.get(cl, 0.0)
    return max(d, 0.020)

# ------------------------------------------------- routed-json net/sink maps
def build_netdb(routed_json):
    """-> (netname->ROUTING attr {sanitized+uniquified as json2ot does},
           cellname->site {sanitized})."""
    d = json.load(open(routed_json))
    m = d["modules"][max(d["modules"], key=lambda k: len(d["modules"][k].get("cells", {})))]
    nets, cells = m.get("netnames", {}), m.get("cells", {})
    routing, used, bit_seen = {}, set(), set()
    for nn, nv in nets.items():
        attr = nv.get("attributes", {}).get("ROUTING", "").strip()
        for b in nv["bits"]:
            if not isinstance(b, int) or b in bit_seen:
                continue
            bit_seen.add(b)
            name = sanitize(nn)
            if name in used:
                name = f"{name}__b{b}"
            used.add(name)
            if attr:
                routing[name] = attr
    site = {}
    for cn, c in cells.items():
        bel = c.get("attributes", {}).get("NEXTPNR_BEL", "")
        if bel and "/" in bel:
            site[sanitize(cn)] = tuple(bel.split("/", 1))   # (site, bel)
    return routing, site

def sink_leaf(cellpin, feats, sitemap):
    """conn sink 'cell:PIN' -> best-matching leaf wire, or None.
    tier 1: leaf sitewire in the cell's site whose name matches the pin
            (LUT pins translate through the bel: A3 on C6LUT -> site pin C3)
    tier 2: any leaf in the cell's site (max delay chosen by caller)"""
    if ":" not in cellpin:
        return None
    cell, pin = cellpin.rsplit(":", 1)
    sb = sitemap.get(cell)
    if not sb:
        return None
    st, bel = sb
    insite = {l.rsplit("/", 1)[-1]: l for l in feats
              if l.startswith(f"SITEWIRE/{st}/")}
    if not insite:
        return None
    cands = [pin]
    m = re.match(r"^A(\d)$", pin)          # stamped LUT input An
    if m and bel and bel[0] in "ABCD" and "LUT" in bel:
        cands.append(bel[0] + m.group(1))  # site pin = <belletter><n>
    if pin == "D" and bel and bel[0] in "ABCD" and "FF" in bel:
        cands.append(bel[0] + "X")         # FF bypass input AX/BX/CX/DX
    for c in cands:
        if c in insite:
            return insite[c]
    return "MAXSITE:" + st                 # caller: max over in-site leaves

# ------------------------------------------------------------------- main
def main():
    fasm, conn, out = sys.argv[1], sys.argv[2], sys.argv[3]
    rjson = sys.argv[4] if len(sys.argv) > 4 else None

    calib = {}
    cf = os.environ.get("OT_CALIB") or os.path.join(HERE, "calib.json")
    if os.path.exists(cf):
        calib = json.load(open(cf))
    W = dict(WIRE_DEFAULT)
    W.update(calib.get("wire", {}))

    conns = [l.rstrip("\n").split("\t") for l in open(conn) if l.strip()]
    nnets = len(conns)

    netfeats = {}
    sitemap = {}
    if rjson and os.path.exists(rjson):
        routing, sitemap = build_netdb(rjson)
        for name, attr in routing.items():
            parent, wires = parse_routing(attr)
            f = leaf_features(parent, wires)
            if f:
                netfeats[name] = f
        src = "fit" if "wire" in calib else "seed"
        print(f"[route2spef] per-net Elmore ({src} constants): route trees for "
              f"{len(netfeats)}/{nnets} nets from {rjson}", file=sys.stderr)
    else:
        # fallback: flat design-wide fanout lump from the FASM pip census
        HOPD, LONGD = 0.060, 0.120
        npips = longp = 0
        for ln in open(fasm, errors="replace"):
            p = ln.strip().split(".")
            if len(p) == 3 and p[0].startswith(("INT_L", "INT_R")):
                npips += 1
                if any(k in p[1] + p[2] for k in ("LH", "LV", "LVB", "6BEG", "6END")):
                    longp += 1
        avg_hops = max(1.0, npips / max(1, nnets))
        avg_hop_delay = (longp * LONGD + (npips - longp) * HOPD) / max(1, npips)
        NETD = avg_hops * avg_hop_delay
        print(f"[route2spef] flat model {NETD:.3f} ns/net (no routed json)", file=sys.stderr)

    stats = collections.Counter()
    with open(out, "w") as f:
        f.write('*SPEF "IEEE 1481-1998"\n*DESIGN "open"\n*DATE "x"\n*VENDOR "x"\n')
        f.write('*PROGRAM "route2spef"\n*VERSION "1.0"\n*DESIGN_FLOW ""\n')
        f.write('*DIVIDER /\n*DELIMITER :\n*BUS_DELIMITER [ ]\n')
        f.write('*T_UNIT 1 NS\n*C_UNIT 1 PF\n*R_UNIT 1 KOHM\n*L_UNIT 1 HENRY\n\n')
        for row in conns:
            net, drv = row[0], row[1]
            snks = row[2].split() if len(row) > 2 else []
            def pinref(x):
                return x[5:] if x.startswith("PORT:") else x
            drvp = pinref(drv)
            snkps = [pinref(s) for s in snks]
            fo = len(snkps)
            # CLOCK nets ride the dedicated low-skew global tree, NOT fabric
            # routing: a fabric-modelled delay fabricates huge capture skew and
            # fake hold violations.  pin-name set must match json2ot.py's CLKS.
            nck = sum(1 for s in snks if s.rsplit(":", 1)[-1] in
                      ("C", "CK", "CLK", "CLKARDCLK", "CLKBWRCLK", "WCLK",
                       "CLKARDCLKL", "CLKARDCLKU", "CLKBWRCLKL", "CLKBWRCLKU"))
            is_clock = fo > 0 and nck * 2 >= fo

            if is_clock:
                dly = [W["clock_lump"]] * fo
                stats["clock"] += 1
            elif net in netfeats:
                feats = netfeats[net]
                maxd = max(feat_delay(ft, W, fo) for ft in feats.values())
                dly = []
                for s in snks:
                    l = sink_leaf(s, feats, sitemap)
                    if l in feats:
                        dly.append(feat_delay(feats[l], W, fo))
                        stats["sink_exact"] += 1
                    elif isinstance(l, str) and l.startswith("MAXSITE:"):
                        st = l[8:]
                        cand = [feat_delay(ft, W, fo) for lw, ft in feats.items()
                                if lw.startswith(f"SITEWIRE/{st}/")]
                        dly.append(max(cand) if cand else maxd)
                        stats["sink_site"] += 1
                    else:
                        dly.append(maxd)
                        stats["sink_netmax"] += 1
                stats["tree"] += 1
            elif netfeats:
                dly = [W["base"]] * fo      # intra-site / unrouted: base only
                stats["notree"] += 1
            else:
                dly = [NETD] * fo
                stats["flat"] += 1

            totcap = C * fo
            f.write(f"*D_NET {net} {totcap:.5f}\n*CONN\n")
            # NB: test the PORT: prefix, NOT ":" in the raw string -- "PORT:x"
            # itself contains a colon; the old test emitted port drivers as
            # instance pins (*I) and broke every port-driven clock rctree.
            f.write(f"*P {drvp} O\n" if drv.startswith("PORT:") else f"*I {drvp} O\n")
            for s in snks:
                f.write(f"*P {pinref(s)} I\n" if s.startswith("PORT:") else f"*I {pinref(s)} I\n")
            f.write("*CAP\n")
            f.write(f"1 {drvp} 0.0\n")
            for i, s in enumerate(snkps, start=2):
                f.write(f"{i} {s} {C:.5f}\n")
            f.write("*RES\n")
            for i, (s, dl) in enumerate(zip(snkps, dly), start=1):
                f.write(f"{i} {drvp} {s} {dl / (C + CPIN):.4f}\n")
            f.write("*END\n\n")
    print(f"[route2spef] wrote {out} ({nnets} nets)  " +
          " ".join(f"{k}={v}" for k, v in sorted(stats.items())), file=sys.stderr)

if __name__ == "__main__":
    main()
