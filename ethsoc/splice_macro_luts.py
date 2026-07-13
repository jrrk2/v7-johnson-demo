#!/usr/bin/env python3
"""Overlay the GOLDEN LUT INITs onto nextpnr's FASM for the stamped hard-macro
slices.  The route-lock + LUT-pin template align each frozen LUT to golden's
physical pin arrangement, but nextpnr's X_ORIG_PORT->INIT permutation mis-emits
the INIT for ~15 A1..A5-swapped LUTs (wrong function).  Since the frozen macro
IS a copy of golden's config (routing already locked from golden), the correct
INIT is simply golden's -- splice it in for every stamped-macro SLICE's LUTs.

usage: splice_macro_luts.py nextpnr.fasm gold_bit2fasm.fasm placement.txt out.fasm
"""
import sys, re, json, glob

def main():
    npnr_fasm, gold_fasm, placement, out = sys.argv[1:5]
    tg = json.load(open(glob.glob('/home/jonathan/prjxray/database/virtex7/xc7vx485t/tilegrid.json')[0]))
    # SLICE name -> (tile, SLICEM/L_X{0,1})
    tile_slices = {}
    for t, i in tg.items():
        for s in i.get('sites', {}):
            if s.startswith('SLICE_'):
                tile_slices.setdefault(t, []).append(s)
    slice2feat = {}
    for t, slist in tile_slices.items():
        for idx, s in enumerate(sorted(slist, key=lambda s: int(re.search(r'X(\d+)', s).group(1)))):
            slice2feat[s] = (t, '%s_X%d' % ('SLICEM' if 'CLBLM' in t else 'SLICEL', idx))
    # stamped-macro slice-feature prefixes (e.g. CLBLM_R_X131Y15.SLICEM_X0)
    stamped = set()
    for line in open(placement):
        p = line.rstrip('\n').split('\t')
        if len(p) < 2:
            continue
        if p[1] in slice2feat:
            t, f = slice2feat[p[1]]
            stamped.add('%s.%s' % (t, f))
    # golden LUT INIT lines for stamped slices, keyed by <tile>.<slice>.<X>LUT.INIT
    def initkey(line):
        m = re.match(r'^(\S+?\.SLICE[ML]_X\d\.[ABCD]LUT)\.INIT', line)
        return m.group(1) if m else None
    def slicepref(line):
        m = re.match(r'^(\S+?\.SLICE[ML]_X\d)\.', line)
        return m.group(1) if m else None
    gold_init = {}
    for line in open(gold_fasm):
        line = line.rstrip('\n')
        k = initkey(line)
        if k and slicepref(line) in stamped:
            gold_init[k] = line
    # replace-in-place: for a stamped-slice LUT that golden ALSO has an INIT for,
    # swap in golden's exact INIT (fixes the mis-permuted ones).  Keep nextpnr's
    # for LUTs golden lacks (route-throughs nextpnr legitimately inserted for the
    # locked routing).  Don't invent INITs for bels neither emitted.
    def popcount(line):
        m = re.search(r"= \d+'b([01]+)", line)
        return m.group(1).count('1') if m else -1
    # Replace ONLY where the function is genuinely CORRUPTED: nextpnr's INIT has a
    # DIFFERENT popcount than golden's.  A pin permutation (template swap of a
    # frozen input to golden's pin) preserves popcount and is functionally correct
    # -- forcing golden's INIT there would break LUTs fed by boundary nets nextpnr
    # legitimately placed on a different pin (e.g. phy_reset_n).  A popcount change
    # means the template's INIT-permutation dropped/mis-mapped an input.
    out_lines = []
    replaced = 0
    for line in open(npnr_fasm):
        raw = line.rstrip('\n')
        k = initkey(raw)
        if k and slicepref(raw) in stamped and k in gold_init and popcount(raw) != popcount(gold_init[k]):
            out_lines.append(gold_init[k])
            replaced += 1
            continue
        out_lines.append(raw)
    open(out, 'w').write('\n'.join(out_lines) + '\n')
    sys.stderr.write("splice_macro_luts: %d stamped slices, replaced %d corrupted LUT INITs with golden\n"
                     % (len(stamped), replaced))

if __name__ == '__main__':
    main()
