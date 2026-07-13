#!/usr/bin/env python3
"""Set BSCAN.JTAG_CHAIN_<n> enable bits (CFG_CENTER_MID segbits 26/27_2162
and 26/27_2163).  The prjxray virtex7 tilegrid has bits:{} for
CFG_CENTER_MID so fasm2frames drops these features; window base 0x00401f00
verified against a Vivado golden (chain1 = bit_00401f1a_067_18).
usage: patch_bscan.py in.frames out.frames [design.fasm]
With a fasm argument, the chains to enable are read from its
BSCAN.JTAG_CHAIN_<n> lines; default is chain 1.
"""
import sys, re

BASE = 0x00401f00
# chain -> (minor, bit index within the 49-/101-word window)
SEGBITS = {1: (26, 2162), 2: (27, 2162), 3: (26, 2163), 4: (27, 2163)}

chains = {1}
if len(sys.argv) > 3:
    chains = set()
    for ln in open(sys.argv[3]):
        m = re.search(r'BSCAN\.JTAG_CHAIN_([1-4])', ln)
        if m:
            chains.add(int(m.group(1)))
    if not chains:
        print('patch_bscan: no BSCAN features in fasm; nothing to do')
        chains = set()

want = {}  # frame -> [(word, bit)]
for c in sorted(chains):
    minor, bitidx = SEGBITS[c]
    want.setdefault(BASE + minor, []).append((bitidx // 32, bitidx % 32))

out = []
done = set()
for ln in open(sys.argv[1]):
    ln = ln.rstrip('\n')
    addr = ln.split(' ', 1)[0]
    try:
        a = int(addr, 16)
    except ValueError:
        out.append(ln)
        continue
    if a in want:
        _, data = ln.split(' ', 1)
        words = [int(w, 16) for w in data.split(',')]
        for wd, bit in want[a]:
            words[wd] |= 1 << bit
        ln = '%s %s' % (addr, ','.join('0x%08X' % w for w in words))
        done.add(a)
    out.append(ln)
for a, bits in want.items():
    if a in done:
        continue
    words = [0] * 101
    for wd, bit in bits:
        words[wd] |= 1 << bit
    out.append('0x%08X %s' % (a, ','.join('0x%08X' % w for w in words)))
open(sys.argv[2], 'w').write('\n'.join(out) + '\n')
print('patch_bscan: chains %s -> frames %s' % (sorted(chains), [hex(a) for a in want]))
