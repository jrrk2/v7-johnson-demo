#!/usr/bin/env python3
# Post-fasm2frames frame patch for the open-flow led[4] output on AR35.
#
# ROOT CAUSE: AR35 (IO_0_VRN_13) sits on the bank-13 *SING* tiles
# (LIOI_SING_X82Y51 / LIOB18_SING_X81Y51), which prjxray's virtex7 fuzzers
# barely covered: segbits_lioi_sing.db has no OLOGIC output-path features,
# and the tilegrid aliases the SING into the regular LIOI segbits with
# start_offset 2.  nextpnr emits OLOGIC_Y0.{OQUSED,OMUX.D1,
# OSERDES.DATA_RATE_TQ.BUF} route-thru features which alias-resolve to
# WRONG physical bits inside the SING window and break the pad's output
# path -> led[4] sticks high.
#
# Proven by raw-frame-diffing the (HW-working) Vivado golden
# vc707_picosoc.bit against the open-flow frames over the whole bank-13
# column (baseaddr 0x00421000):
#   - golden sets NO OLOGIC config in the SING window (words 99-100): the
#     D1->OQ pass-through needs no bits on a SING tile (on the regular
#     LIOI tiles golden *does* set OQUSED/OMUX.D1, same as we do, and
#     those LEDs work).
#   - the only ours-only bits in the window are the three below.
#   - (Golden's extra 23/24_99_21 bits are just its IMUX_L34.ER1END1 route
#     encoding in INT_L_X32Y49, which shares words 99-100 - do NOT copy
#     them; our route uses NE2END1.)
#
# FIX (AR35 tile only; absolute addresses are fixed for this pin):
#   CLEAR frame 0x0042101F word 99 bit 22   (misaliased OLOGIC_Y0.OQUSED)
#   CLEAR frame 0x00421020 word 99 bit  2   (misaliased ...DATA_RATE_TQ.BUF)
#   CLEAR frame 0x00421021 word 100 bit 15  (misaliased OLOGIC_Y0.OMUX.D1)
#
# usage: patch_led4_iob.py <in.frames> <out.frames>
import sys
PATCH = {0x0042101F: [(99, 22, 0)],
         0x00421020: [(99, 2, 0)],
         0x00421021: [(100, 15, 0)]}
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
    sys.stderr.write("patch_led4_iob: patched frames %s\n" % sorted(hex(a) for a in done))
if __name__ == '__main__':
    main()
