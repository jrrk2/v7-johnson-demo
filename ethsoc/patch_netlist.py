#!/usr/bin/env python3
"""Make a Vivado write_verilog netlist yosys-readable:

1. Module-header port expressions `.A(B),` (Vivado's pushed-inverter
   _sp_/_sn_ aliases and similar) -> plain port `A` + an `assign` alias
   next to the body's direction declaration of the internal net B.
2. SRLC32E `.Q31(net)` -> `.Q(net)` (all instances in these netlists
   have A=5'b11111, where Q == Q31).

usage: patch_netlist.py in.v out.v
"""
import re, sys

def main():
    src = open(sys.argv[1]).read().split('\n')
    out = []
    inhdr = False
    pending = {}   # module-scope: internal net -> port name
    hdr_re = re.compile(r'^(\s*)\.\s*(\\?[A-Za-z_0-9$\[\]]+?)\s*\(\s*(\\?[A-Za-z_0-9$\[\]]+?)\s*\)\s*(,|\);)\s*$')
    n = 0
    txt = '\n'.join(src)
    # IOSTANDARD("DEFAULT") parameters on IO buffers carry no information
    # (the XDC is authoritative) but make nextpnr's IO config emission fire
    # both the diff and the default single-ended paths -> fasm2frames
    # clear/set conflict on the pad tile.
    txt = re.sub(r'#\(\s*\.IOSTANDARD\("DEFAULT"\)\)\s*', '', txt)
    txt = re.sub(r'\.IOSTANDARD\("DEFAULT"\),\s*', '', txt)
    # Vivado write_verilog can name a 2-D net (e.g. a FIFO storage array
    # exposed as a hierarchical port) "\foo[i][j]".  yosys's escaped-id
    # parser chokes on the "][" adjacency ("Interface found" / "port not
    # declared in header").  Flatten the bracket pair to "_i_j" uniformly
    # across the whole file so header, declaration and the parent
    # instantiation all rename in lockstep.  Range selects [a:b] are
    # untouched (no "][" adjacency).
    txt = re.sub(r'\[(\d+)\]\[(\d+)\]', r'_\1_\2', txt)
    src = txt.split('\n')
    # SRLC32E .Q31 -> .Q is only valid for a TERMINAL SRL (A=11111 -> Q==Q31).
    # For a CASCADE SRL (Q31 net also consumed on a .D) the shiftout must ride the
    # dedicated MC31 cascade into the next SRL's DI mux; the patched nextpnr maps
    # SRLC32E.Q31 -> the MC31 port (port_xform) and routes MC31 -> ?DI1MUX -> DI1.
    # Rewriting it to .Q would instead present the (unroutable, non-cascade) O6
    # output, so keep .Q31 whenever its net is also a .D sink.
    q31_nets = set(re.findall(r'\.Q31\s*\(\s*(\S+?)\s*\)', txt))
    d_nets   = set(re.findall(r'\.D\s*\(\s*(\S+?)\s*\)', txt))
    keep_q31 = q31_nets & d_nets
    q31_line = re.compile(r'\.Q31\s*\(\s*(\S+?)\s*\)')
    for ln in src:
        mq = q31_line.search(ln)
        if not (mq and mq.group(1) in keep_q31):
            ln = ln.replace('.Q31(', '.Q(')
        if re.match(r'\s*module\s', ln):
            inhdr = True
            pending = {}
        if inhdr:
            m = hdr_re.match(ln)
            if m:
                ind, port, net, term = m.groups()
                pending[net.strip()] = port.strip()
                out.append('%s%s%s' % (ind, port, term))
                n += 1
                if term == ');':
                    inhdr = False
                continue
            if ');' in ln:
                inhdr = False
                out.append(ln)
                continue
        md = re.match(r'^(\s*)(input|output)\s+(\\?[A-Za-z_0-9$\[\]]+?)\s*;\s*$', ln)
        if md and md.group(3).strip() in pending:
            ind, dirn, net = md.group(1), md.group(2), md.group(3).strip()
            port = pending[net]
            sep = ' ' if net.startswith('\\') else ''
            out.append('%s%s %s;' % (ind, dirn, port))
            if dirn == 'output':
                out.append('%sassign %s = %s%s;' % (ind, port, net, sep))
            else:
                out.append('%sassign %s%s = %s;' % (ind, net, sep, port))
            continue
        out.append(ln)
    open(sys.argv[2], 'w').write('\n'.join(out))
    print('patched %d header port-expressions' % n)

if __name__ == '__main__':
    main()
