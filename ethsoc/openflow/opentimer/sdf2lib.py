#!/usr/bin/env python3
"""Build an OpenTimer-readable Liberty (.lib) for the xc7 fabric cells used by
the open-flow netlists, with per-arc delays taken from the prjxray SDF timing
data (real xc7 silicon timing; RapidWright ships no 7-series delay model).

Scalar (constant) NLDM arcs = the SDF worst-case (slow, ::-second) numbers.
Interconnect delay is modelled separately in SPEF (see route2spef.py).

usage: sdf2lib.py <out.lib>
"""
import re, sys, glob, os

SDF_DIR = os.path.expanduser("~/prjxray/database/virtex7/timings")

# ---- parse SDF: {celltype: {(ipath,opath):(rise_slow,fall_slow)},
#                             (SETUP/HOLD): {(pin):value} } ----
def parse_sdf(path):
    txt = open(path).read()
    cells = {}
    # split into CELL blocks
    for m in re.finditer(r'\(CELL\s+\(CELLTYPE "([^"]+)"\)(.*?)(?=\(CELL |\Z)', txt, re.S):
        ct, body = m.group(1), m.group(2)
        d = cells.setdefault(ct, {"iopath": {}, "setup": {}, "hold": {}})
        for io in re.finditer(r'\(IOPATH\s+(\S+)\s+(\S+)\s+\(([-\d.]+)::([-\d.]+)\)\s*\(([-\d.]+)::([-\d.]+)\)', body):
            ip, op = io.group(1), io.group(2)
            rise_slow = float(io.group(4)); fall_slow = float(io.group(6))
            d["iopath"][(ip, op)] = (rise_slow, fall_slow)
        for tc, kind in (("SETUP", "setup"), ("HOLD", "hold")):
            for s in re.finditer(rf'\({tc}\s+(\S+)\s+\((?:pos|neg)edge\s+(\S+)\)\s+\(([-\d.]+)::([-\d.]+)\)', body):
                d[kind][(s.group(1), s.group(2))] = float(s.group(4))
    return cells

SDF = {}
for f in ("CLBLL_L", "CLBLM_L", "BRAM_L", "CLK_BUFG_BOT_R", "LIOB33"):
    p = f"{SDF_DIR}/{f}.sdf"
    if os.path.exists(p):
        for k, v in parse_sdf(p).items():
            SDF.setdefault(k, v)

def arc(ct, ip, op, default=(0.05, 0.10)):
    e = SDF.get(ct, {}).get("iopath", {})
    return e.get((ip, op), default)

# LUT reference arc (all LUT inputs -> O, from LUT6)
LUT_A = arc("LUT6", "A1", "O6", (0.045, 0.100))
FF_CQ = arc("REG_INIT_FF", "CLK", "Q", (0.139, 0.340))
FF_SU = SDF.get("REG_INIT_FF", {}).get("setup", {}).get(("DIN", "CLK"), -0.046)
FF_HD = SDF.get("REG_INIT_FF", {}).get("hold", {}).get(("DIN", "CLK"), 0.225)
CE_SU = SDF.get("REG_INIT_FF", {}).get("setup", {}).get(("CE", "CLK"), 0.109)
CE_HD = SDF.get("REG_INIT_FF", {}).get("hold", {}).get(("CE", "CLK"), -0.009)
BUFG_D = arc("BUFGCTRL", "I", "O", (0.029, 0.096))

# ---- Liberty emission ----
L = []
def w(s=""): L.append(s)

w('library (xc7fabric) {')
w('  delay_model : table_lookup;')
w('  time_unit : "1ns";')
w('  voltage_unit : "1V";')
w('  current_unit : "1mA";')
w('  capacitive_load_unit (1,pf);')
w('  pulling_resistance_unit : "1kohm";')
w('  default_max_transition : 1.0;')
w('  lu_table_template (scalar) { variable_1 : total_output_net_capacitance; index_1 ("0.0"); }')
w('  lu_table_template (cst) { variable_1 : constrained_pin_transition; variable_2 : related_pin_transition; index_1 ("0.0"); index_2 ("0.0"); }')
w('  slew_lower_threshold_pct_rise : 20;')
w('  slew_upper_threshold_pct_rise : 80;')
w('  slew_lower_threshold_pct_fall : 20;')
w('  slew_upper_threshold_pct_fall : 80;')
w('  input_threshold_pct_rise : 50; input_threshold_pct_fall : 50;')
w('  output_threshold_pct_rise : 50; output_threshold_pct_fall : 50;')

def scalar(v): return f'("{max(v,0.001):.4f}")'

def comb_arc(rel, rise, fall):
    r = f'{max(rise,0.001):.4f}'; fl = f'{max(fall,0.001):.4f}'
    w('      timing () {')
    w(f'        related_pin : "{rel}";')
    w(f'        cell_rise (scalar) {{ values ("{r}"); }}')
    w(f'        cell_fall (scalar) {{ values ("{fl}"); }}')
    w('        rise_transition (scalar) { values ("0.010"); }')
    w('        fall_transition (scalar) { values ("0.010"); }')
    w('      }')

def out_pin(name, arcs):   # arcs: list of (related_pin, rise, fall)
    w(f'    pin ({name}) {{ direction : output;')
    for rel, r, fnl in arcs: comb_arc(rel, r, fnl)
    w(f'    }}')

def in_pin(name, cap=0.001):
    w(f'    pin ({name}) {{ direction : input; capacitance : {cap}; }}')

# --- LUT1..6 ---
for n in range(1, 7):
    w(f'  cell (LUT{n}) {{')
    for i in range(n): in_pin(f'I{i}')
    out_pin('O', [(f'I{i}', LUT_A[0], LUT_A[1]) for i in range(n)])
    w('  }')

# --- MUXF7/MUXF8 (treat as combinational, small delay) ---
for mux in ("MUXF7", "MUXF8"):
    w(f'  cell ({mux}) {{')
    for p in ("I0", "I1", "S"): in_pin(p)
    out_pin('O', [('I0', 0.05, 0.06), ('I1', 0.05, 0.06), ('S', 0.06, 0.07)])
    w('  }')

# --- FF family: FDRE/FDSE/FDPE/FDCE ---
for ff in ("FDRE", "FDSE", "FDPE", "FDCE"):
    w(f'  cell ({ff}) {{')
    w('    ff (IQ,IQN) { clocked_on : "C"; next_state : "D"; }')
    in_pin('CE')
    rstpin = 'R' if ff == 'FDRE' else 'S' if ff == 'FDSE' else 'PRE' if ff == 'FDPE' else 'CLR'
    in_pin(rstpin)
    w('    pin (C) { direction : input; clock : true; capacitance : 0.001; }')
    cq = f'{max(FF_CQ[0],0.001):.4f}'
    su = f'{max(FF_SU,0.001):.4f}'; hd = f'{max(FF_HD,0.001):.4f}'
    w('    pin (Q) { direction : output;')
    w('      timing () { related_pin : "C"; timing_type : rising_edge;')
    w(f'        cell_rise (scalar) {{ values ("{cq}"); }} cell_fall (scalar) {{ values ("{cq}"); }}')
    w('        rise_transition (scalar) { values ("0.010"); } fall_transition (scalar) { values ("0.010"); } }')
    w('    }')
    w('    pin (D) { direction : input; capacitance : 0.001;')
    w('      timing () { related_pin : "C"; timing_type : setup_rising;')
    w(f'        rise_constraint (cst) {{ values ("{su}"); }} fall_constraint (cst) {{ values ("{su}"); }} }}')
    w('      timing () { related_pin : "C"; timing_type : hold_rising;')
    w(f'        rise_constraint (cst) {{ values ("{hd}"); }} fall_constraint (cst) {{ values ("{hd}"); }} }}')
    w('    }')
    w('  }')

# --- CARRY4 (scalar pins CI,CYINIT,DI0..3,S0..3 -> O0..3,CO0..3) ---
w('  cell (CARRY4) {')
for p in ('CI','CYINIT','DI0','DI1','DI2','DI3','S0','S1','S2','S3'): in_pin(p)
SDFPIN = {'CI': 'CIN'}   # lib pin -> SDF pin name
def cval(libip, op):
    v = arc('CARRY4', SDFPIN.get(libip, libip), op, None)
    return v
for j in range(4):
    for outp in (f'O{j}', f'CO{j}'):
        arcs = []
        for ip in ('CI', 'CYINIT', f'S{j}'):
            v = cval(ip, outp)
            if v: arcs.append((ip, v[0], v[1]))
        if not arcs: arcs = [('CI', 0.15, 0.40)]
        out_pin(outp, arcs)
w('  }')
BUS = ['  # (bus type not needed: CARRY4 uses scalar pins)']

# --- RAMB36E1 (BRAM): superset indexed pins; clk->DO, in->clk setup ---
BRAM_CQ = 0.500   # clk -> DOUT (BRAM_L.sdf CLKARDCLK->DOADO ~0.4-1.1ns; slow ~0.5)
BRAM_SU = 0.200   # ADDR/DI/WE -> CLK setup
BRAM_HD = 0.100
def wide_cell(name, clocks, inbuses, outbuses, cq, su, hd):
    w(f'  cell ({name}) {{')
    for ck in clocks:
        w(f'    pin ({ck}) {{ direction : input; clock : true; capacitance : 0.001; }}')
    # scalar control inputs get a plain setup to the first clock
    ck0 = clocks[0]
    for base, wdt in inbuses:
        for i in range(wdt):
            pn = f'{base}{i}' if wdt > 1 else base
            w(f'    pin ({pn}) {{ direction : input; capacitance : 0.001;')
            w(f'      timing () {{ related_pin : "{ck0}"; timing_type : setup_rising;')
            w(f'        rise_constraint (cst) {{ values ("{su:.4f}"); }} fall_constraint (cst) {{ values ("{su:.4f}"); }} }}')
            w(f'      timing () {{ related_pin : "{ck0}"; timing_type : hold_rising;')
            w(f'        rise_constraint (cst) {{ values ("{max(hd,0.001):.4f}"); }} fall_constraint (cst) {{ values ("{max(hd,0.001):.4f}"); }} }}')
            w('    }')
    for base, wdt, ck in outbuses:
        for i in range(wdt):
            pn = f'{base}{i}' if wdt > 1 else base
            w(f'    pin ({pn}) {{ direction : output;')
            w(f'      timing () {{ related_pin : "{ck}"; timing_type : rising_edge;')
            w(f'        cell_rise (scalar) {{ values ("{cq:.4f}"); }} cell_fall (scalar) {{ values ("{cq:.4f}"); }}')
            w('        rise_transition (scalar) { values ("0.010"); } fall_transition (scalar) { values ("0.010"); } }')
            w('    }')
    w('  }')

wide_cell('RAMB36E1', ['CLKARDCLK', 'CLKBWRCLK'],
    [('ADDRARDADDR',16),('ADDRBWRADDR',16),('DIADI',32),('DIBDI',32),
     ('DIPADIP',4),('DIPBDIP',4),('WEA',4),('WEBWE',8),
     ('ENARDEN',1),('ENBWREN',1),('REGCEAREGCE',1),('REGCEB',1),
     ('RSTRAMARSTRAM',1),('RSTRAMB',1),('RSTREGARSTREG',1),('RSTREGB',1)],
    [('DOADO',32,'CLKARDCLK'),('DOBDO',32,'CLKBWRCLK'),
     ('DOPADOP',4,'CLKARDCLK'),('DOPBDOP',4,'CLKBWRCLK')],
    BRAM_CQ, BRAM_SU, BRAM_HD)

# --- SRL16E / SRLC32E: clk->Q + addr(A*)->Q comb mux; D->CLK setup ---
for srl, awid in (('SRL16E', 0), ('SRLC32E', 5)):  # SRL16E uses A0..A3 scalars
    w(f'  cell ({srl}) {{')
    w('    pin (CLK) { direction : input; clock : true; capacitance : 0.001; }')
    w('    pin (CE) { direction : input; capacitance : 0.001; }')
    w('    pin (D) { direction : input; capacitance : 0.001;')
    w('      timing () { related_pin : "CLK"; timing_type : setup_rising;')
    w(f'        rise_constraint (cst) {{ values ("0.100"); }} fall_constraint (cst) {{ values ("0.100"); }} }}')
    w('      timing () { related_pin : "CLK"; timing_type : hold_rising;')
    w(f'        rise_constraint (cst) {{ values ("0.100"); }} fall_constraint (cst) {{ values ("0.100"); }} }}')
    w('    }')
    apins = [f'A{i}' for i in range(4)] if srl == 'SRL16E' else [f'A{i}' for i in range(awid)]
    for a in apins: in_pin(a)
    outs = ['Q'] + (['Q31'] if srl == 'SRLC32E' else [])
    for o in outs:
        w(f'    pin ({o}) {{ direction : output;')
        w('      timing () { related_pin : "CLK"; timing_type : rising_edge;')
        w('        cell_rise (scalar) { values ("0.400"); } cell_fall (scalar) { values ("0.400"); }')
        w('        rise_transition (scalar) { values ("0.010"); } fall_transition (scalar) { values ("0.010"); } }')
        for a in apins: comb_arc(a, 0.25, 0.25)
        w('    }')
    w('  }')

# --- RAM64M / RAM32M distributed RAM: comb read ADDR*->DO*, write DI*->WCLK ---
for rm, awid, dwid in (('RAM64M', 6, 1), ('RAM32M', 5, 2)):
    w(f'  cell ({rm}) {{')
    w('    pin (WCLK) { direction : input; clock : true; capacitance : 0.001; }')
    w('    pin (WE) { direction : input; capacitance : 0.001; }')
    ports = ['A','B','C','D']
    for pt in ports:
        aw = awid if rm == 'RAM64M' else (awid if pt == 'D' else 2)
        for i in range(aw):
            an = f'ADDR{pt}{i}' if aw > 1 else f'ADDR{pt}'
            in_pin(an)
        for i in range(dwid):
            din = f'DI{pt}{i}' if dwid > 1 else f'DI{pt}'
            w(f'    pin ({din}) {{ direction : input; capacitance : 0.001;')
            w('      timing () { related_pin : "WCLK"; timing_type : setup_rising;')
            w('        rise_constraint (cst) { values ("0.100"); } fall_constraint (cst) { values ("0.100"); } }')
            w('      timing () { related_pin : "WCLK"; timing_type : hold_rising;')
            w('        rise_constraint (cst) { values ("0.100"); } fall_constraint (cst) { values ("0.100"); } }')
            w('    }')
    for pt in ('A','B','C'):
        aw = awid if rm == 'RAM64M' else 2
        for i in range(dwid):
            do = f'DO{pt}{i}' if dwid > 1 else f'DO{pt}'
            arcs = [(f'ADDR{pt}{j}' if aw > 1 else f'ADDR{pt}', 0.25, 0.25) for j in range(aw)]
            out_pin(do, arcs)
    w('  }')

# --- BUFG / IBUF / OBUF / IBUFDS (pass-through) ---
for cell, ip, op in (('BUFG','I','O'), ('IBUF','I','O'), ('OBUF','I','O')):
    w(f'  cell ({cell}) {{')
    in_pin(ip)
    if cell == 'BUFG':
        w(f'    pin (I) {{ direction : input; clock : true; capacitance : 0.001; }}')
    out_pin(op, [(ip, BUFG_D[0], BUFG_D[1])])
    w('  }')
# IBUFDS: two inputs I,IB -> O
w('  cell (IBUFDS) {'); in_pin('I'); in_pin('IB'); out_pin('O', [('I',0.05,0.05)]); w('  }')

w('}')

# insert bus type after library header (before first cell) -- OpenTimer wants it early
out = "\n".join(L)
out = out.replace("  lu_table_template (scalar)", BUS[0] + "\n  lu_table_template (scalar)")
open(sys.argv[1], "w").write(out + "\n")
print(f"wrote {sys.argv[1]}")
print(f"  LUT arc(slow rise/fall) = {LUT_A}")
print(f"  FF  clk->Q = {FF_CQ}  setup(D)={FF_SU}  hold(D)={FF_HD}")
print(f"  BUFG I->O = {BUFG_D}")
