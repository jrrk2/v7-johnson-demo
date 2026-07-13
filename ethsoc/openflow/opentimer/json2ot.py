#!/usr/bin/env python3
"""Flattened nextpnr/yosys JSON -> OpenTimer netlist + matching Liberty + conn.

Generic: uses each cell's port_directions; buses are per-bit in JSON (expanded
to indexed scalar pins); GT/PHY primitives are CUT (their fabric nets become
primary inputs).  Cell arc delays from the prjxray-SDF families (real xc7).

usage: json2ot.py <flat.json> <out_prefix>   -> <pfx>.v <pfx>.lib <pfx>.conn
"""
import sys, json, collections

flat, pfx = sys.argv[1], sys.argv[2]
d = json.load(open(flat))
m = d["modules"][max(d["modules"], key=lambda k: len(d["modules"][k].get("cells", {})))]
cells, nets = m["cells"], m.get("netnames", {})

# bit -> net name
bit2name = {}
for nn, nv in nets.items():
    for b in nv["bits"]:
        if isinstance(b, int):
            bit2name.setdefault(b, nn.replace("$", "_").replace(".", "_").replace(":", "_")
                                  .replace("[", "_").replace("]", "").replace("\\", "").replace("/", "_"))
def netof(b):
    if b in ("0", 0): return "const0"
    if b in ("1", 1): return "const1"
    return bit2name.get(b, f"n{b}")

CLKS = {"C", "CK", "CLK", "CLKARDCLK", "CLKBWRCLK", "WCLK"}
CUT = {"MMCME2_ADV", "IBUFDS", "IBUFDS_GTE2", "GTXE2_COMMON", "GTXE2_CHANNEL",
       "IOBUF", "PLLE2_ADV", "BSCANE2", "BUFH", "BUFR", "BUFMR", "BUFIO",
       # clock buffers: cut so their output clock nets become clean PIs that
       # create_clock can drive (otherwise the un-modeled BUFGCTRL poisons every
       # FF clock arrival with nan -- the ethloop full-chip STA blockage).
       "BUFGCTRL", "BUFGCE", "BUFGMUX", "BUFGMUX_CTRL", "BUFG"}
SEQ = {"FDRE", "FDSE", "FDPE", "FDCE", "RAMB36E1", "RAMB18E1", "SRL16E", "SRLC32E"}
# combinational everything else in fabric (LUT*, MUXF*, CARRY4, RAMD*, RAMS*, BUFG/IBUF/OBUF)

# optional calibration: {celltype: {"cq":x,"su":x,"hd":x,"comb":x}} from the
# golden Vivado SDF (sdf_calibrate.py).  Overrides the prjxray-SDF defaults.
import os
CALIB = {}
_cf = os.environ.get("OT_CALIB") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "calib.json")
if os.path.exists(_cf):
    CALIB = json.load(open(_cf))
    print(f"[json2ot] using calibration for {len(CALIB)} cell types from " + _cf + "", file=sys.stderr)

# delay families (slow/worst-case, ns)
def famdelay(typ):
    if typ in CALIB:                      # calibrated from golden Vivado SDF
        base = _famdelay_default(typ); base.update(CALIB[typ]); return base
    return _famdelay_default(typ)
def _famdelay_default(typ):
    if typ.startswith("LUT"): return dict(comb=0.100)
    if typ.startswith("MUXF"): return dict(comb=0.060)
    if typ == "CARRY4": return dict(comb=0.150)
    if typ.startswith(("RAMD", "RAMS")): return dict(comb=0.250)     # async LUTRAM read
    if typ in ("BUFG", "IBUF", "OBUF"): return dict(comb=0.096)
    if typ in ("FDRE","FDSE","FDPE","FDCE"): return dict(cq=0.139, su=0.050, hd=0.225)
    if typ.startswith("RAMB"): return dict(cq=0.500, su=0.200, hd=0.100)
    if typ.startswith("SRL"): return dict(cq=0.400, su=0.100, hd=0.100)
    return dict(comb=0.100)

def out_clock(typ, pin):
    if typ.startswith("RAMB"):
        if pin.startswith(("DOA","DOPA")): return "CLKARDCLK"
        if pin.startswith(("DOB","DOPB")): return "CLKBWRCLK"
    return "CLK" if "CLK" in [p for p in ("CLK",) ] else "C"

# ---- pass 1: collect per-type pin sets (name -> dir), instances ----
typepins = collections.defaultdict(dict)   # type -> {expanded_pin: dir}
insts = []                                  # (type, name, [(pin, net, dir)])
def sanitize(s):
    return s.replace("$","_").replace(".","_").replace(":","_").replace("[","_").replace("]","").replace("\\","").replace("/","_")

for cn, cell in cells.items():
    typ = cell["type"]
    if typ in ("VCC", "GND"): continue
    pd = cell.get("port_directions", {})
    conns = cell["connections"]
    name = sanitize(cn)
    flat_pins = []
    for pin, bits in conns.items():
        dirn = pd.get(pin, "input")
        if len(bits) == 1:
            flat_pins.append((pin, netof(bits[0]), dirn))
            if typ not in CUT: typepins[typ][pin] = dirn
        else:
            for i, b in enumerate(bits):     # yosys JSON is LSB-first
                pn = f"{pin}{i}"
                flat_pins.append((pn, netof(b), dirn))
                if typ not in CUT: typepins[typ][pn] = dirn
    insts.append((typ, name, flat_pins))

# ---- emit lib ----
def clockpin(typ):
    for p in typepins[typ]:
        base = "".join(ch for ch in p if not ch.isdigit())
        if base in CLKS: return p
    return None

L = ['library (xc7auto) {', '  delay_model : table_lookup;',
     '  time_unit : "1ns"; voltage_unit : "1V"; current_unit : "1mA";',
     '  capacitive_load_unit (1,pf); pulling_resistance_unit : "1kohm";',
     '  default_max_transition : 1.0;',
     '  lu_table_template (scalar) { variable_1 : total_output_net_capacitance; index_1 ("0.0"); }',
     '  lu_table_template (cst) { variable_1 : constrained_pin_transition; variable_2 : related_pin_transition; index_1 ("0.0"); index_2 ("0.0"); }',
     '  input_threshold_pct_rise : 50; input_threshold_pct_fall : 50;',
     '  output_threshold_pct_rise : 50; output_threshold_pct_fall : 50;',
     '  slew_lower_threshold_pct_rise : 20; slew_upper_threshold_pct_rise : 80;',
     '  slew_lower_threshold_pct_fall : 20; slew_upper_threshold_pct_fall : 80;']
def sv(x): return f'("{max(x,0.001):.4f}")'
for typ, pins in typepins.items():
    if typ in CUT: continue
    fd = famdelay(typ)
    ck = clockpin(typ)
    outs = [p for p, dr in pins.items() if dr == "output"]
    ins  = [p for p, dr in pins.items() if dr != "output"]
    L.append(f'  cell ({typ}) {{')
    seq = typ in SEQ and ck is not None
    if typ in ("FDRE","FDSE","FDPE","FDCE") and ck:
        nxt = "D" if "D" in pins else next((p for p in pins if pins[p]!="output" and p not in CLKS), "D")
        L.append(f'    ff (IQ,IQN) {{ clocked_on : "{ck}"; next_state : "{nxt}"; }}')
    for p in ins:
        base = "".join(ch for ch in p if not ch.isdigit())
        is_clk = base in CLKS
        if is_clk:
            L.append(f'    pin ({p}) {{ direction : input; clock : true; capacitance : 0.001; }}')
        elif seq and base not in ("R", "S", "PRE", "CLR", "CE", "RSTRAMARSTRAM",
                                  "RSTRAMB", "RSTREGARSTREG", "RSTREGB", "REGCEAREGCE",
                                  "REGCEB", "ENARDEN", "ENBWREN", "WE", "WEA", "WEBWE"):
            # async set/reset + often-constant control pins (CE/EN/WE) get no
            # setup/hold: they're frequently tied to const -> spurious hold viols
            L.append(f'    pin ({p}) {{ direction : input; capacitance : 0.001;')
            L.append(f'      timing () {{ related_pin : "{ck}"; timing_type : setup_rising; rise_constraint (cst) {{ values {sv(fd["su"])}; }} fall_constraint (cst) {{ values {sv(fd["su"])}; }} }}')
            L.append(f'      timing () {{ related_pin : "{ck}"; timing_type : hold_rising; rise_constraint (cst) {{ values {sv(fd["hd"])}; }} fall_constraint (cst) {{ values {sv(fd["hd"])}; }} }}')
            L.append('    }')
        else:
            L.append(f'    pin ({p}) {{ direction : input; capacitance : 0.001; }}')
    for p in outs:
        L.append(f'    pin ({p}) {{ direction : output;')
        if seq:
            oc = ck
            if typ.startswith("RAMB"):
                oc = "CLKARDCLK" if p.startswith(("DOA","DOPA")) else ("CLKBWRCLK" if p.startswith(("DOB","DOPB")) else ck)
            L.append(f'      timing () {{ related_pin : "{oc}"; timing_type : rising_edge; cell_rise (scalar) {{ values {sv(fd["cq"])}; }} cell_fall (scalar) {{ values {sv(fd["cq"])}; }} rise_transition (scalar) {{ values ("0.01"); }} fall_transition (scalar) {{ values ("0.01"); }} }}')
        else:
            dl = fd.get("comb", 0.1)
            rels = [q for q in ins if "".join(ch for ch in q if not ch.isdigit()) not in CLKS]
            # CARRY4: restrict to CI/CYINIT/S; RAMD: RADR/ADR only
            if typ == "CARRY4":
                rels = [q for q in ins if q.startswith(("CI","CYINIT","S"))]
            elif typ.startswith(("RAMD","RAMS")):
                rels = [q for q in ins if q.startswith(("RADR","ADR"))]
            for r in rels[:8]:
                L.append(f'      timing () {{ related_pin : "{r}"; cell_rise (scalar) {{ values {sv(dl)}; }} cell_fall (scalar) {{ values {sv(dl)}; }} rise_transition (scalar) {{ values ("0.01"); }} fall_transition (scalar) {{ values ("0.01"); }} }}')
        L.append('    }')
    L.append('  }')
L.append('}')
open(os.environ.get("OT_LIB_OUT", pfx+".lib"), "w").write("\n".join(L)+"\n")

# ---- emit netlist ----
driven, allnets, opins = set(), {"const0","const1"}, set()
net_drv, net_snk = {}, {}
emit = []
for typ, name, flat_pins in insts:
    if typ in CUT: continue
    conn = ", ".join(f".{p}({n})" for p, n, _ in flat_pins)
    for p, n, dr in flat_pins:
        allnets.add(n)
        if dr == "output":
            driven.add(n); net_drv[n] = f"{name}:{p}"
        else:
            net_snk.setdefault(n, []).append(f"{name}:{p}")
        if typ == "OBUF" and dr == "output": opins.add(n)
    emit.append(f"{typ} {name} ( {conn} );")

pis = sorted(n for n in allnets if n not in driven and n not in opins)  # incl const0/1
pos = sorted(opins)
out = [f"module top ( {', '.join(pis+pos)} );"]
out += [f"input {p};" for p in pis] + [f"output {p};" for p in pos]
out += [f"wire {n};" for n in sorted(allnets) if n not in pis and n not in pos]
out += emit + ["endmodule"]
open(pfx+".v", "w").write("\n".join(out)+"\n")

with open(pfx+".conn", "w") as f:
    for n in sorted(allnets):
        if n in ("const0","const1"): continue
        drv = net_drv.get(n) or (f"PORT:{n}" if n in pis else None)
        if not drv: continue
        snk = list(net_snk.get(n, [])) + ([f"PORT:{n}"] if n in pos else [])
        if snk: f.write(f"{n}\t{drv}\t{' '.join(snk)}\n")

print(f"json2ot: {len(emit)} cells, {len(pis)} PIs, {len(pos)} POs, {len(typepins)} cell types")
print(f"  clocks by type: " + ", ".join(f"{t}:{clockpin(t)}" for t in sorted(typepins) if clockpin(t))[:200])
