#!/usr/bin/env python3
"""Convert a Vivado structural netlist (write_verilog -mode design) into a flat
OpenTimer-parseable Verilog: strip #() params, expand CARRY4 buses to bits,
tie VCC/GND to const nets, and CUT non-fabric primitives (MMCME2_ADV, IBUFDS*,
GTXE2*, IOBUF) -- their fabric-facing nets become primary inputs (clock/data
sources).  Emits <out.v> and <out.nets> (net list for route2spef).

usage: netlist2ot.py <in_netlist.v> <top> <out.v>
"""
import sys, re

src, top, outv = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(src).read()

# ---- crude Verilog instance tokenizer ----
# collapse to the module body
m = re.search(rf'module\s+{re.escape(top)}\s*\((.*?)\);(.*?)endmodule', txt, re.S)
body = m.group(2)

# strip attributes (* ... *) and parameter blocks #( ... ) (one nesting level)
body = re.sub(r'\(\*.*?\*\)', ' ', body, flags=re.S)
body = re.sub(r'#\s*\((?:[^()]|\([^()]*\))*\)', ' ', body, flags=re.S)

CUT = {"MMCME2_ADV", "IBUFDS", "IBUFDS_GTE2", "GTXE2_COMMON", "GTXE2_CHANNEL",
       "IOBUF", "BSCANE2", "PLLE2_ADV"}
PASS = {"BUFG", "IBUF", "OBUF"}      # single I->O
FAB  = {"LUT1","LUT2","LUT3","LUT4","LUT5","LUT6","FDRE","FDSE","FDPE","FDCE",
        "CARRY4","MUXF7","MUXF8"}
# wide (bus-pin) cells: expand each >1-bit connection to indexed scalar pins
WIDE = {"RAMB36E1","SRL16E","SRLC32E","RAM64M","RAM32M"}
OUTBASE = {"RAMB36E1": {"DOADO","DOBDO","DOPADOP","DOPBDOP"},
           "SRL16E": {"Q"}, "SRLC32E": {"Q","Q31"},
           "RAM64M": {"DOA","DOB","DOC","DOD"}, "RAM32M": {"DOA","DOB","DOC","DOD"}}

def clean_net(n):
    n = n.strip().replace("\\", "").strip()
    if n in ("1'b0", "1'h0"): return "const0"
    if n in ("1'b1", "1'h1"): return "const1"
    if n in ("<const0>", "<const1>"): return n.strip("<>")
    n = n.replace("[", "_").replace("]", "").replace(" ", "")
    return n

def split_conc(s):   # {a,b,c} -> [a,b,c]; handle ranges a[4:1] left as-is bit-expand later
    s = s.strip()
    if s.startswith("{"):
        s = s[1:-1]
    # split on top-level commas
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch == "{": depth += 1
        if ch == "}": depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur); cur = ""
        else: cur += ch
    if cur.strip(): parts.append(cur)
    return [p.strip() for p in parts]

def bit_expand(tok):
    """expand a[4:1] into [a_4,a_3,a_2,a_1] (MSB first)."""
    tok = tok.strip()
    mm = re.match(r'^(\S+?)\[(\d+):(\d+)\]$', tok)
    if mm:
        base, hi, lo = mm.group(1), int(mm.group(2)), int(mm.group(3))
        step = -1 if hi >= lo else 1
        return [clean_net(f"{base}[{i}]") for i in range(hi, lo+step, step)]
    return [clean_net(tok)]

# find instances: TYPE  instname ( .pin(net), ... ) ;
inst_re = re.compile(r'\b([A-Z][A-Z0-9_]+)\s+(\\?\S+?)\s*\((.*?)\)\s*;', re.S)
pin_re  = re.compile(r'\.(\w+)\s*\(\s*(.*?)\s*\)\s*(?:,|$)', re.S)

cells = []          # (type, name, [(pin, [bits])])
nets = set()
consts = {"const0", "const1"}

for im in inst_re.finditer(body):
    typ, name, conns = im.group(1), im.group(2), im.group(3)
    if typ not in (FAB | PASS | WIDE | CUT | {"VCC","GND"}): continue
    name = clean_net(name)
    pins = []
    for pm in pin_re.finditer(conns):
        pin, val = pm.group(1), pm.group(2)
        toks = split_conc(val)
        bits = []
        for t in toks: bits += bit_expand(t)
        pins.append((pin, bits))
    cells.append((typ, name, pins))

# ---- resolve: which nets are driven by CUT cells (-> primary inputs) ----
driven_by_cut = set()
for typ, name, pins in cells:
    if typ in CUT:
        for pin, bits in pins:
            # outputs of cut cells drive fabric: treat all their nets as PI
            for b in bits: driven_by_cut.add(b)

OUTPINS = {"O","Q","O0","O1","O2","O3","CO0","CO1","CO2","CO3"}
# ---- emit OpenTimer verilog ----
emit = []
allnets = set(["const0","const1"])
driven = set()
opins = set()   # nets driven by OBUF (primary outputs)

_unc = [0]
def san(n):
    if ":" in n or "UNCONNECTED" in n:
        _unc[0] += 1; return f"unconn_{_unc[0]}"
    return n
def carry_pins(pins):
    d = dict(pins)
    res = [("CI", san(d.get("CI",["const0"])[0])),
           ("CYINIT", san(d.get("CYINIT",["const0"])[0]))]
    for busp in ("DI","S","O","CO"):
        bl = d.get(busp, [])
        for i, b in enumerate(bl):          # bl MSB-first (index len-1..0)
            idx = len(bl)-1-i
            res.append((f"{busp}{idx}", san(b)))
    return res

net_drv = {}      # net -> "cell:pin" (driver)
net_snk = {}      # net -> ["cell:pin", ...] (sinks)
def wide_pins(typ, pins):
    """expand bus pins to indexed scalar pins (base<idx>, MSB-first)."""
    res, outs = [], OUTBASE.get(typ, set())
    for base, bits in pins:
        if len(bits) == 1:
            res.append((base, san(bits[0]), base in outs))
        else:
            for i, b in enumerate(bits):
                idx = len(bits)-1-i
                res.append((f"{base}{idx}", san(b), base in outs))
    return res

for typ, name, pins in cells:
    if typ in CUT or typ in ("VCC","GND"): continue
    if typ == "CARRY4":
        flat = [(p, n, p in OUTPINS) for p, n in carry_pins(pins)]
    elif typ in WIDE:
        flat = wide_pins(typ, pins)
    else:
        flat = [(p, b[0] if b else "const0", p in OUTPINS) for p, b in pins]
    conn = ", ".join(f".{p}({n})" for p, n, _ in flat)
    for p, n, isout in flat:
        allnets.add(n)
        if isout:
            driven.add(n); net_drv[n] = f"{name}:{p}"
        else:
            net_snk.setdefault(n, []).append(f"{name}:{p}")
        if typ == "OBUF" and p == "O": opins.add(n)
    emit.append(f"{typ} {name} ( {conn} );")

# undriven, used nets -> primary inputs (const0/1, clock sources, cut outputs)
pis = sorted(n for n in allnets if n not in driven and n not in opins)
pos = sorted(opins)
out = [f"module top ( {', '.join(pis + pos)} );"]
for p in pis: out.append(f"input {p};")
for p in pos: out.append(f"output {p};")
for n in sorted(allnets):
    if n not in pis and n not in pos:
        out.append(f"wire {n};")
out += emit
out.append("endmodule")

open(outv, "w").write("\n".join(out) + "\n")
open(outv.replace(".v", ".nets"), "w").write("\n".join(sorted(allnets - {"const0","const1"} - set(pis))) + "\n")
# connectivity: net  driver  sink1 sink2 ...   (driver may be PORT:<port> for a PI)
pis_set = set(pis); pos_set = set(pos)
with open(outv.replace(".v", ".conn"), "w") as f:
    for n in sorted(allnets):
        if n in ("const0","const1"): continue
        drv = net_drv.get(n)
        if drv is None:
            if n in pis_set: drv = f"PORT:{n}"
            else: continue
        snks = list(net_snk.get(n, []))
        if n in pos_set: snks.append(f"PORT:{n}")
        if not snks: continue
        f.write(f"{n}\t{drv}\t{' '.join(snks)}\n")
print(f"wrote {outv}: {len(emit)} cells, {len(pis)} primary inputs, {len(allnets)} nets")
