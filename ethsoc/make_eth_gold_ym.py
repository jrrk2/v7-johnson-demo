#!/usr/bin/env python3
"""Post-process the golden write_verilog dump of the whole `eth` block
(framing_top_sgmii + eth_macro) into a yosys-readable netlist:

  1. patch_netlist.py fixups (header port aliases, SRLC32E Q31, IOSTANDARD,
     2-D net bracket flattening)
  2. EM_-prefix every module DEFINED in the file except the top
     (framing_top_sgmii), so the frozen block's internal module names cannot
     collide with anything in the user synthesis and stay self-contained.

usage: make_eth_gold_ym.py raw.v out.v   (top module = framing_top_sgmii)
"""
import re, sys, subprocess, os, tempfile

TOP = 'framing_top_sgmii'
here = os.path.dirname(os.path.abspath(__file__))

def main():
    raw, out = sys.argv[1], sys.argv[2]
    # 1. run patch_netlist.py raw -> tmp
    tmp = tempfile.NamedTemporaryFile('w', suffix='.v', delete=False).name
    subprocess.check_call([sys.executable, os.path.join(here, 'patch_netlist.py'), raw, tmp])
    src = open(tmp).read().split('\n')
    os.unlink(tmp)
    # 2. collect defined module names
    defined = set()
    for ln in src:
        m = re.match(r'^module\s+(\w+)', ln)
        if m:
            defined.add(m.group(1))
    rename = {n for n in defined if n != TOP}
    print("modules defined: %d, EM_-prefixing %d (top=%s)" % (len(defined), len(rename), TOP))
    # 3. rewrite module defs + instantiations
    outl = []
    for ln in src:
        m = re.match(r'^module\s+(\w+)', ln)
        if m and m.group(1) in rename:
            outl.append('module EM_' + ln[len('module '):].lstrip())
            continue
        # instantiation: first non-space token is a defined (non-top) module,
        # followed by whitespace and an instance name / parameter list
        mi = re.match(r'^(\s+)(\w+)(\s+|\s*#)', ln)
        if mi and mi.group(2) in rename:
            outl.append('%sEM_%s%s' % (mi.group(1), mi.group(2), ln[mi.end(2):]))
            continue
        outl.append(ln)
    open(out, 'w').write('\n'.join(outl))
    print("wrote", out)

if __name__ == '__main__':
    main()
