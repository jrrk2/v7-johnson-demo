#!/usr/bin/env python3
"""Structural diff: SVS-emitted sgmii_soc.edf vs golden pcs_pma_flat.v.
Instances matched by normalized name; compares celltype, INIT, and per-pin
net ADJACENCY (the set of other endpoints on the net feeding each pin)."""
import re, sys
from collections import defaultdict

def norm_gold(n):
    n = n.strip().lstrip('\\').strip()
    n = n.replace('/', '_').replace('[', '_').replace(']', '_').replace('.', '_')
    n = re.sub(r'_+$', '_', n)
    return n

# ---------------- golden verilog netlist parse ----------------
gtext = open('/home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v').read()
# strip attributes
gtext = re.sub(r'\(\*.*?\*\)', '', gtext, flags=re.S)
inst_re = re.compile(
    r'\n\s*([A-Z][A-Z0-9_]*)\s*(#\s*\((?:[^()]|\([^()]*\))*\))?\s*'
    r'((?:\\\S+\s)|\w+)\s*\(((?:[^();]|\([^()]*\))*)\);', re.S)
pin_re = re.compile(r'\.(\w+)\s*\(([^()]*(?:\([^()]*\))?[^()]*)\)')

gold_inst = {}          # norm name -> (celltype, init, [(pin, netexpr)])
gold_netpins = defaultdict(list)  # net string -> [(inst, pin)]
for m in inst_re.finditer(gtext):
    ct, params, nm, body = m.group(1), m.group(2) or '', m.group(3), m.group(4)
    nm_n = norm_gold(nm)
    init = ''
    im = re.search(r'\.INIT\s*\(\s*([^)\s]+)\s*\)', params)
    if im: init = im.group(1)
    pins = []
    for pm in pin_re.finditer(body):
        pin, net = pm.group(1), pm.group(2).strip()
        pins.append((pin, net))
        gold_netpins[net].append((nm_n, pin))
    gold_inst[nm_n] = (ct, init, pins)

# ---------------- SVS EDIF parse ----------------
etext = open('/tmp/eb/hybrid3/sgmii_soc.edf').read()
PFX = 'i_pcs_pma_258__inst__'
svs_cell = {}    # inst -> celltype
svs_init = {}
for m in re.finditer(r'\(instance (\S+) \(viewref netlist \(cellref (\S+) ', etext):
    svs_cell[m.group(1)] = m.group(2)
for m in re.finditer(r'\(instance (\S+) [^\n]*\n((?:\s*\(property[^\n]*\n)*)', etext):
    pm = re.search(r'\(property INIT \((?:string "?([^")]+)"?|integer (\d+))\)', m.group(2))
    if pm: svs_init[m.group(1)] = pm.group(1) or pm.group(2)

def sexp_span(text, start):
    """return end index of the balanced s-expr opening at text[start]=='('"""
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == '(': depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0: return i + 1
    return len(text)

svs_netpins = {}  # net -> [(inst,pin)]
svs_pin2net = {}
for m in re.finditer(r'\(net (\S+)\s*\(joined', etext):
    net = m.group(1)
    body = etext[m.start():sexp_span(etext, m.start())]
    eps = []
    for pr in re.finditer(r'\(portref (?:\(member ([^\s)]+) (\d+)\)|([^\s)]+))(?:\s*\(instanceref ([^\s)]+)\))?\)', body):
        pin = pr.group(1) or pr.group(3)
        if pr.group(2) is not None: pin = '%s[%s]' % (pin, pr.group(2))
        inst = pr.group(4) or '<port>'
        eps.append((inst, pin))
        svs_pin2net[(inst, pin)] = net
    svs_netpins[net] = eps

def svs_norm(inst):
    if inst.startswith(PFX): return inst[len(PFX):]
    return None   # outside pcs region

# instances in pcs region only
svs_pcs = {svs_norm(i): i for i in svs_cell if svs_norm(i)}

FOCUS = sys.argv[1] if len(sys.argv) > 1 else ''
gold_focus = {n: v for n, v in gold_inst.items() if FOCUS in n}

missing, extra, ct_diff, init_diff = [], [], [], []
for n, (ct, init, pins) in gold_focus.items():
    if n not in svs_pcs:
        # golden GND/VCC/buf cells may legitimately be tie-folded
        if ct not in ('GND', 'VCC'):
            missing.append((n, ct))
        continue
    si = svs_pcs[n]
    sct = svs_cell[si]
    if sct != ct: ct_diff.append((n, ct, sct))
    sini = svs_init.get(si, '')
    def caninit(x):
        x = x.strip('"').lower()
        m = re.match(r"(\d+)'h([0-9a-f]+)", x)
        if m: return int(m.group(2), 16)
        m = re.match(r"(\d+)'b([01]+)", x)
        if m: return int(m.group(2), 2)
        try: return int(x)
        except: return x
    if init and caninit(init) != caninit(sini):
        init_diff.append((n, init, sini))
svs_only = [n for n in svs_pcs if FOCUS in n and n not in gold_inst
            and svs_cell[svs_pcs[n]] not in ('GND', 'VCC')]

print('gold instances (focus=%r): %d   svs pcs instances: %d' % (FOCUS, len(gold_focus), len(svs_pcs)))
print('MISSING in svs: %d' % len(missing))
for n, ct in missing[:25]: print('   ', ct, n)
print('EXTRA in svs (focus): %d' % len(svs_only))
for n in svs_only[:15]: print('   ', svs_cell[svs_pcs[n]], n)
print('CELLTYPE diff: %d' % len(ct_diff))
for d in ct_diff[:15]: print('   ', d)
print('INIT diff: %d' % len(init_diff))
for d in init_diff[:25]: print('   ', d)

# ---------------- suffix matching + adjacency diff ----------------
unmatched_gold = [n for n in gold_focus if n not in svs_pcs]
unmatched_svs  = [n for n in svs_pcs if n not in gold_inst]
sfx_map = {}
by_sfx = {}
for s in unmatched_svs: by_sfx.setdefault(s.split('__')[-1], []).append(s)
for g in unmatched_gold:
    cands = [s for s in unmatched_svs if s.endswith('_' + g) or s.endswith('__' + g) or s.split('__')[-1] == g]
    if len(cands) == 1: sfx_map[g] = cands[0]
print('suffix-matched %d of %d unmatched gold' % (len(sfx_map), len(unmatched_gold)))

full_map = {}   # gold name -> svs name (normed)
for n in gold_focus:
    if n in svs_pcs: full_map[n] = n
    elif n in sfx_map: full_map[n] = sfx_map[n]
inv_map = {v: k for k, v in full_map.items()}

# celltype/INIT on suffix-matched
ct2, in2 = 0, 0
for g, s in sfx_map.items():
    ct, init, _ = gold_inst[g]
    if svs_cell[svs_pcs[s]] != ct: ct2 += 1; print('CT2', g, ct, svs_cell[svs_pcs[s]])
for g, s in sfx_map.items():
    ct, init, _ = gold_inst[g]
    sini = svs_init.get(svs_pcs[s], '')
    def caninit(x):
        x = x.strip('"').lower()
        m = re.match(r"(\d+)'h([0-9a-f]+)", x)
        if m: return int(m.group(2), 16)
        m = re.match(r"(\d+)'b([01]+)", x)
        if m: return int(m.group(2), 2)
        try: return int(x)
        except: return x
    if init and caninit(init) != caninit(sini): in2 += 1; print('INIT2', g, init, sini)
print('suffix-matched celltype diffs %d  init diffs %d' % (ct2, in2))

# adjacency: golden net endpoints (mapped) vs svs net endpoints (mapped)
gold_pin2net = {}
for net, eps in gold_netpins.items():
    for inst, pin in eps: gold_pin2net[(inst, pin)] = net
def gold_adj(g, pin):
    net = gold_pin2net.get((g, pin));
    if net is None: return None
    if re.match(r"^1'b[01]$", net.strip()): return frozenset([('CONST', net.strip()[-1])])
    return frozenset((i if i in full_map else 'UNMATCHED:' + i, p)
                     for i, p in gold_netpins[net] if (i, p) != (g, pin))
def svs_adj(g, pin):
    s = svs_pcs.get(full_map.get(g)); 
    if s is None: return None
    net = svs_pin2net.get((s, pin))
    if net is None: return None
    if net == 'n_GND': return frozenset([('CONST', '0')])
    if net == 'n_VCC': return frozenset([('CONST', '1')])
    out = set()
    for i, p in svs_netpins[net]:
        if (i, p) == (s, pin): continue
        n2 = svs_norm(i)
        out.add((inv_map.get(n2, 'UNMATCHED:' + str(n2)), p))
    return frozenset(out)

diffs = 0
for g in sorted(full_map):
    ct, _, pins = gold_inst[g]
    for pin, netexpr in pins:
        ga, sa = gold_adj(g, pin), svs_adj(g, pin)
        if ga is None or sa is None: continue
        if ga != sa:
            only_g = ga - sa; only_s = sa - ga
            # ignore pure naming noise: both sides all-unmatched
            sig_g = {x for x in only_g if not str(x[0]).startswith('UNMATCHED')}
            sig_s = {x for x in only_s if not str(x[0]).startswith('UNMATCHED')}
            if not sig_g and not sig_s: continue
            diffs += 1
            if diffs <= 40:
                print('ADJ %s %s.%s' % (ct, g, pin))
                if sig_g: print('    gold-only:', sorted(sig_g)[:6])
                if sig_s: print('    svs-only :', sorted(sig_s)[:6])
print('ADJACENCY diffs (significant): %d' % diffs)

# ---------------- driver-focused diff ----------------
OUT_PINS = {'LUT1':{'O'},'LUT2':{'O'},'LUT3':{'O'},'LUT4':{'O'},'LUT5':{'O'},'LUT6':{'O'},
  'FDRE':{'Q'},'FDSE':{'Q'},'FDPE':{'Q'},'FDCE':{'Q'},'FD':{'Q'},'FDP':{'Q'},'FDC':{'Q'},'FDE':{'Q'},
  'CARRY4':{'O','CO'},'MUXF7':{'O'},'MUXF8':{'O'},'SRL16E':{'Q','Q15'},'SRLC32E':{'Q','Q31'},
  'RAM32X1S':{'O'},'RAM64X1S':{'O'},'RAM128X1S':{'O'},'RAM32X1D':{'SPO','DPO'},'RAM64X1D':{'SPO','DPO'},
  'RAM128X1D':{'SPO','DPO'},'RAM32M':{'DOA','DOB','DOC','DOD'},'RAM64M':{'DOA','DOB','DOC','DOD'},
  'BUFG':{'O'},'BUFH':{'O'},'BUFR':{'O'},'IBUF':{'O'},'OBUF':{'O'},'IBUFDS':{'O'},'OBUFDS':{'O'},
  'LUT6_2':{'O5','O6'},'XORCY':{'O'},'MUXCY':{'O'},'VCC':{'P'},'GND':{'G'}}
GT_OUTS = re.compile(r'^(RXDATA|RXCHARISK|RXCHARISCOMMA|RXDISPERR|RXNOTINTABLE|RXOUTCLK|TXOUTCLK|'
  r'RXRESETDONE|TXRESETDONE|RXPMARESETDONE|RXBUFSTATUS|TXBUFSTATUS|RXBYTEISALIGNED|RXBYTEREALIGN|'
  r'RXCOMMADET|RXELECIDLE|CPLLLOCK|CPLLREFCLKLOST|DRPDO|DRPRDY|GTREFCLKMONITOR|RXCLKCORCNT|'
  r'RXCDRLOCK|RXPRBSERR|PHYSTATUS|RXVALID|RXSTATUS|TXGEARBOXREADY|TXQPISENP|TXQPISENN|LOCKED|'
  r'CLKOUT\d|CLKFBOUT|O)\b')
def pin_base(p): return p.split('[')[0]
def is_out(ct, pin):
    b = pin_base(pin)
    if ct in OUT_PINS: return b in OUT_PINS[ct]
    return bool(GT_OUTS.match(b))   # GT/MMCM/unknown macros

def gold_driver(net):
    for i, p in gold_netpins[net]:
        ct = gold_inst.get(i, ('?','',''))[0]
        if is_out(ct, p): return (i if i in full_map else 'UNM:'+i, pin_base(p))
    if re.match(r"^1'b[01]$", net.strip()): return ('CONST', net.strip()[-1])
    return ('NONE','')
def svs_driver(net):
    if net=='n_GND': return ('CONST','0')
    if net=='n_VCC': return ('CONST','1')
    for i, p in svs_netpins[net]:
        ct = svs_cell.get(i, '?')
        if is_out(ct, p):
            n2 = svs_norm(i)
            return (inv_map.get(n2, 'UNM:'+str(n2)), pin_base(p))
    return ('NONE','')

dd = 0
for g in sorted(full_map):
    ct, _, pins = gold_inst[g]
    s = svs_pcs.get(full_map[g])
    for pin, netexpr in pins:
        if is_out(ct, pin): continue
        gnet = gold_pin2net.get((g, pin)); snet = svs_pin2net.get((s, pin_base(pin)))
        if gnet is None or snet is None: continue
        gd, sd = gold_driver(gnet), svs_driver(snet)
        if gd != sd:
            # same instance different alias name = fine if mapped names equal
            if gd[0] == sd[0] and gd[1] == sd[1]: continue
            dd += 1
            if dd <= 40: print('DRV %-6s %s.%s   gold<=%s.%s   svs<=%s.%s' % (ct, g, pin, gd[0], gd[1], sd[0], sd[1]))
print('DRIVER diffs: %d' % dd)
