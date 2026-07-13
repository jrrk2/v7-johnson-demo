#!/usr/bin/env python3
"""Overlay golden SLICE config (FF init/reset, FFMUX, OUTMUX, CARRY, etc.) onto
the PURE-macro slices (slices occupied ONLY by frozen eth cells, no arp_ctrl /
route-thru).  nextpnr's imported-cell FASM path mis-emits these for stamped
cells (FF ZINI/ZRST, FFMUX O6-vs-AX, OUTMUX) -> the frozen FFs power up /
capture / drive the wrong thing.  The macro's routing is locked to golden, so
golden's per-slice config is the correct one.

EXCLUDES *LUT.INIT -- that is handled by splice_macro_luts.py (popcount-selective)
because some frozen LUTs are fed by BOUNDARY nets nextpnr legitimately placed on
a different pin, where golden's INIT would be wrong.  FF/mux config is intra-slice
(matches the locked routing) so it is safe to force to golden.

usage: splice_macro_config.py in.fasm gold_bit2fasm.fasm pure_slices.txt out.fasm
"""
import sys, re

def main():
    in_fasm, gold_fasm, pure_file, out = sys.argv[1:5]
    pure = set(l.strip() for l in open(pure_file) if l.strip())

    def slicepref(line):
        m = re.match(r'^(\S+?\.SLICE[ML]_X\d)\.', line)
        return m.group(1) if m else None
    def is_lut_init(line):
        return re.match(r'^\S+?\.SLICE[ML]_X\d\.[ABCD]LUT\.INIT', line) is not None

    # golden config lines for pure slices, keyed by the full feature (before '=')
    gold_cfg = {}          # feature-key -> full golden line
    gold_by_slice = {}     # slice-pref -> set of feature-keys golden has
    for line in open(gold_fasm):
        line = line.rstrip('\n')
        sp = slicepref(line)
        if sp in pure and not is_lut_init(line):
            key = line.split(' = ')[0] if ' = ' in line else line
            gold_cfg[key] = line
            gold_by_slice.setdefault(sp, set()).add(key)

    out_lines = []
    dropped = 0
    for line in open(in_fasm):
        raw = line.rstrip('\n')
        sp = slicepref(raw)
        if sp in pure and not is_lut_init(raw):
            dropped += 1
            continue  # nextpnr's per-slice config replaced wholesale by golden's
        out_lines.append(raw)
    added = 0
    for key in sorted(gold_cfg):
        out_lines.append(gold_cfg[key])
        added += 1
    open(out, 'w').write('\n'.join(out_lines) + '\n')
    sys.stderr.write("splice_macro_config: %d pure slices, dropped %d nextpnr cfg lines, spliced %d golden cfg lines\n"
                     % (len(pure), dropped, added))

if __name__ == '__main__':
    main()
