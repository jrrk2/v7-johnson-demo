#!/usr/bin/env python3
# Splice the GT-column config frames from the HW-golden Vivado bitstream
# into open-flow frames.  The GTX quad-113 configuration is static for our
# fixed pcs_pma IP config and identical between flows; prjxray's virtex7
# tilegrid has no frame addresses for GTX tiles (bits:{}) so fasm2frames
# drops the (otherwise known) GTXE2 segbit features.  Evidence: the ONLY
# golden frame addresses unknown to the tilegrid are these four
# (0x00424C9C..0x00424C9F, minors 28-31 of the quad-113 column), and
# 895/1077 GT-region fasm lines are ppips needing no bits at all.
#
# usage: splice_gt_frames.py <golden.bits> <in.frames> <out.frames>
import sys

GT_FRAMES = [0x00424C9C, 0x00424C9D, 0x00424C9E, 0x00424C9F]
NWORDS = 101

def main():
    goldenbits, inf, outf = sys.argv[1], sys.argv[2], sys.argv[3]
    golden = {a: [0] * NWORDS for a in GT_FRAMES}
    for ln in open(goldenbits):
        p = ln.strip().split('_')      # bit_<frameaddr>_<word>_<bit>
        fa = int(p[1], 16)
        if fa in golden:
            golden[fa][int(p[2])] |= 1 << int(p[3])

    present = set()
    entries = []   # (addr, line) - keep the file address-sorted
    for line in open(inf):
        line = line.rstrip('\n')
        if not line:
            continue
        a_s, w_s = line.split(' ', 1)
        a = int(a_s, 16)
        if a in golden:
            entries.append((a, a_s + ' ' + ','.join('0x%08X' % x for x in golden[a])))
            present.add(a)
        else:
            entries.append((a, line))
    missing = [a for a in GT_FRAMES if a not in present]
    for a in missing:
        entries.append((a, '0x%08X ' % a + ','.join('0x%08X' % x for x in golden[a])))
    entries.sort(key=lambda e: e[0])
    open(outf, 'w').write('\n'.join(l for _, l in entries) + '\n')
    sys.stderr.write("splice_gt_frames: replaced %d, inserted %d GT frames\n"
                     % (len(present), len(missing)))

if __name__ == '__main__':
    main()
