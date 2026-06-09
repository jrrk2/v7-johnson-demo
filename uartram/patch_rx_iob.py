#!/usr/bin/env python3
# Post-fasm2frames frame patch for the open-flow UART rx input (AU33).
#
# ROOT CAUSE: prjxray's virtex7 segbit DB mis-encodes the LVCMOS18 input on the
# HP-bank slave-site pin AU33 (tile LIOB18_X81Y33, baseaddr 0x00421000).  It
# omits an undocumented input-enable bit that Vivado sets, and sets a spurious
# IBUF_HP_BANK_GLUE bit instead -> the rx input drifts on long bit-runs (e.g.
# 0x00->0xff, 0x41->0x5f), corrupting received UART bytes.  Proven by: the
# *Vivado* fasm round-tripped through prjxray distorts identically, and patching
# these two bits makes a bare rx->tx loopback 100% clean for all byte patterns.
#
# FIX (rx tile LIOB18_X81Y33 only; absolute addresses are fixed for AU33):
#   SET   frame 0x0042101C word 63 bit 18   (undocumented rx-input bit, tile 28_18)
#   CLEAR frame 0x0042101D word 66 bit 13   (spurious IBUF_HP_BANK_GLUE Y0, tile 29_109)
#
# usage: patch_rx_iob.py <in.frames> <out.frames>
import sys
PATCH = {0x0042101C: [(63, 18, 1)],   # set
         0x0042101D: [(66, 13, 0)]}   # clear
def main():
    inf, outf = sys.argv[1], sys.argv[2]
    done = set(); out = []
    for line in open(inf):
        line = line.rstrip('\n')
        if not line:
            out.append(line); continue
        a_s, w_s = line.split(' ', 1); a = int(a_s, 16)
        if a in PATCH:
            w = [int(x, 16) for x in w_s.split(',')]
            for wi, bi, setit in PATCH[a]:
                w[wi] = (w[wi] | (1 << bi)) if setit else (w[wi] & ~(1 << bi))
            out.append(a_s + ' ' + ','.join('0x%08X' % x for x in w)); done.add(a)
        else:
            out.append(line)
    open(outf, 'w').write('\n'.join(out) + '\n')
    sys.stderr.write("patch_rx_iob: patched frames %s\n" % sorted(hex(a) for a in done))
if __name__ == '__main__':
    main()
