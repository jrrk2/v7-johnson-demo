#!/usr/bin/env python3
"""Flattened nextpnr/yosys JSON -> OpenTimer netlist + matching Liberty + conn.

Generic: uses each cell's port_directions; buses are per-bit in JSON (expanded
to indexed scalar pins); GT/PHY primitives are CUT (their fabric nets become
primary inputs).  Cell arc delays from the prjxray-SDF families (real xc7).

usage: json2ot.py <flat.json> <out_prefix>   -> <pfx>.v <pfx>.lib <pfx>.conn
"""
import sys, json, re, collections

flat, pfx = sys.argv[1], sys.argv[2]
d = json.load(open(flat))
m = d["modules"][max(d["modules"], key=lambda k: len(d["modules"][k].get("cells", {})))]
cells, nets = m["cells"], m.get("netnames", {})

def sanitize(s):
    return s.replace("$","_").replace(".","_").replace(":","_").replace("[","_").replace("]","").replace("\\","").replace("/","_")

# bit -> net name.  Sanitization can COLLIDE distinct nets (e.g. yosys emits
# both "i_arp.sender_mac[0]" and "i_arp.sender_mac_0" for different bits ->
# both sanitize to i_arp_sender_mac_0): the verilog then merges two nets into
# one multi-driven wire while the conn/SPEF keeps one driver, and OpenTimer
# reports "pin X not found in rctree Y".  Uniquify with a __b<bit> suffix.
bit2name = {}
_used_names = set()
for nn, nv in nets.items():
    for b in nv["bits"]:
        if isinstance(b, int) and b not in bit2name:
            name = sanitize(nn)
            if name in _used_names:
                name = f"{name}__b{b}"
            bit2name[b] = name
            _used_names.add(name)
def netof(b):
    if b in ("0", 0): return "const0"
    if b in ("1", 1): return "const1"
    return bit2name.get(b, f"n{b}")

CLKS = {"C", "CK", "CLK", "CLKARDCLK", "CLKBWRCLK", "WCLK"}
def pinbase(typ, p):
    """digit-stripped pin base; RAMB repack splits pins into L/U halves
    (CLKARDCLKL/CLKARDCLKU etc) -- strip the half suffix for RAMB types."""
    base = "".join(ch for ch in p if not ch.isdigit())
    if typ.startswith("RAMB") and len(base) > 2 and base.endswith(("L", "U")):
        base = base[:-1]
    return base
CUT = {"MMCME2_ADV", "IBUFDS", "IBUFDS_GTE2", "GTXE2_COMMON", "GTXE2_CHANNEL",
       "IOBUF", "PLLE2_ADV", "BSCANE2"}
# clock buffers: cut ONLY when the output actually drives clock pins, so the
# clock nets become clean PIs that create_clock can drive (otherwise the
# un-modeled BUFGCTRL poisons every FF clock arrival with nan -- the ethloop
# full-chip STA blockage).  A BUFG on a RESET/CE net (nextpnr $cebuf$*,
# Vivado _57x_) is a DATA-path buffer: cutting it hid the whole
# FF->route->BUFG->fo~99 reset cone (64% of the Vivado top-400 endpoints are
# its FF S/R sinks) and OT saw ~0.4x of the real path.  Keep those.
CLKBUF = {"BUFGCTRL", "BUFGCE", "BUFGMUX", "BUFGMUX_CTRL", "BUFG",
          "BUFH", "BUFR", "BUFMR", "BUFIO"}
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
# (cell names use the same sanitize() defined above for nets)

for cn, cell in cells.items():
    typ = cell["type"]
    if typ in ("VCC", "GND"): continue
    # nextpnr's packer REWRITES Unisim types to site-slot types on the stamped
    # netlist (FDRE->SLICE_FFX, LUT6->SLICE_LUTX, MUXF7->SELMUX2_1,
    # RAMB36E1->RAMB36E1_RAMB36E1, OBUF->IOB18_OUTBUF_DCIEN, ...).  Classify
    # by X_ORIG_TYPE so SEQ/CUT/calibration still see the logical primitive —
    # a SLICE_FFX modelled as combinational leaves the design with NO clocked
    # endpoint (WNS nan, "no critical path found").  Pin names stay the
    # repacked ones (CK/CLK are already in CLKS).
    etyp = cell.get("attributes", {}).get("X_ORIG_TYPE") or typ
    if etyp in ("VCC", "GND"): continue
    pd = cell.get("port_directions", {})
    conns = cell["connections"]
    name = sanitize(cn)
    flat_pins = []
    for pin, bits in conns.items():
        dirn = pd.get(pin, "input")
        if len(bits) == 1:
            flat_pins.append((pin, netof(bits[0]), dirn))
            if etyp not in CUT and etyp not in CLKBUF: typepins[etyp][pin] = dirn
        else:
            for i, b in enumerate(bits):     # yosys JSON is LSB-first
                pn = f"{pin}{i}"
                flat_pins.append((pn, netof(b), dirn))
                if etyp not in CUT and etyp not in CLKBUF: typepins[etyp][pn] = dirn
    insts.append((etyp, name, flat_pins))

# ---- decide which clock buffers to CUT: only those driving clock pins ----
CLKSINKS = CLKS | {"CLKARDCLKL", "CLKARDCLKU", "CLKBWRCLKL", "CLKBWRCLKU"}
net_clksink = collections.Counter()          # net -> #clock-pin sinks
for etyp, name, flat_pins in insts:
    if etyp in CUT or etyp in CLKBUF: continue
    for p, n, dr in flat_pins:
        if dr != "output" and pinbase(etyp, p) in CLKSINKS:
            net_clksink[n] += 1
cutcells = set()
nkept = 0
for etyp, name, flat_pins in insts:
    if etyp not in CLKBUF: continue
    outnets = [n for p, n, dr in flat_pins if dr == "output"]
    if any(net_clksink.get(n, 0) for n in outnets):
        cutcells.add(name)                   # real clock buffer: cut
    else:                                    # reset/CE buffer: keep as comb
        nkept += 1
        for p, n, dr in flat_pins:
            typepins[etyp][p] = dr
print(f"json2ot: clock buffers cut {len(cutcells)}, kept as data buffers {nkept}", file=sys.stderr)

# ---- emit lib ----
def clockpin(typ):
    for p in typepins[typ]:
        if pinbase(typ, p) in CLKS: return p
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
        base = pinbase(typ, p)
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
                want = "CLKARDCLK" if p.startswith(("DOA","DOPA")) else ("CLKBWRCLK" if p.startswith(("DOB","DOPB")) else None)
                # repacked RAMBs split the clock into L/U half-pins
                # (CLKARDCLKL/CLKARDCLKU): related_pin must be a REAL pin
                if want:
                    oc = next((q for q in ins if q.startswith(want)), ck)
            L.append(f'      timing () {{ related_pin : "{oc}"; timing_type : rising_edge; cell_rise (scalar) {{ values {sv(fd["cq"])}; }} cell_fall (scalar) {{ values {sv(fd["cq"])}; }} rise_transition (scalar) {{ values ("0.01"); }} fall_transition (scalar) {{ values ("0.01"); }} }}')
        else:
            dl = fd.get("comb", 0.1)
            rels = [q for q in ins if "".join(ch for ch in q if not ch.isdigit()) not in CLKS]
            # CARRY4: restrict to CI/CYINIT/S; RAMD: RADR/ADR only
            if typ == "CARRY4":
                rels = [q for q in ins if q.startswith(("CI","CYINIT","S"))]
            elif typ.startswith(("RAMD","RAMS")):
                rels = [q for q in ins if q.startswith(("RADR","ADR"))]
            elif typ in CLKBUF:              # kept data-path BUFG: I0/I1 -> O
                rels = [q for q in ins if re.fullmatch(r"I\d?", q)]
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
    if typ in CUT or name in cutcells: continue
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
