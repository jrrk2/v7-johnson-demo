#!/usr/bin/env python3
"""Translate a Vivado placement dump into SVS/nextpnr cell names.

dump_flat.tcl writes, from ONE routed checkpoint, both
  - ibex_vc707.edf        (write_edif: cells appear as
                           `(instance (rename VALIDID "ORIGINAL") ...)`)
  - placement_ibex.txt    (get_cells: keyed by Vivado's ORIGINAL name)

SVS reads the EDIF and names every cell by the rename VALIDID (the EDIF-legal
identifier), so the JSON nextpnr sees uses VALIDID.  The placement dump uses
ORIGINAL, so a naive match drops every cell whose ORIGINAL needed EDIF escaping
(leading '_' -> '&_...', '.'/'[' ']' rewrites, etc.) -- 132 LUTs here, which
then float and get scattered by the placer, breaking carry CYINIT/DI/S routes.

Build the ORIGINAL->VALIDID map straight from the EDIF (the authoritative,
same-checkpoint source) and rewrite column 0 of the placement file with it, so
every placed primitive matches its JSON cell exactly.

usage: edif_rename_placement.py ibex_vc707.edf placement_ibex.txt placement_ibex_svs.txt
"""
import re, sys

def main():
    edf, plin, plout = sys.argv[1], sys.argv[2], sys.argv[3]
    orig2valid = {}
    re_ren = re.compile(r'\(instance \(rename (\S+) "([^"]*)"\)')
    re_bare = re.compile(r'\(instance (\S+) \(viewref')
    with open(edf) as f:
        for line in f:
            m = re_ren.search(line)
            if m:
                orig2valid[m.group(2)] = m.group(1)
                continue
            m = re_bare.search(line)
            if m:
                orig2valid[m.group(1)] = m.group(1)
    n = miss = 0
    with open(plin) as fi, open(plout, 'w') as fo:
        for line in fi:
            parts = line.rstrip('\n').split('\t')
            if len(parts) < 2:
                continue
            name = parts[0]
            valid = orig2valid.get(name)
            if valid is None:
                miss += 1
                continue   # cell not in the EDIF (e.g. macro leaf) -> skip
            parts[0] = valid
            fo.write('\t'.join(parts) + '\n')
            n += 1
    print('wrote %d placement entries (%d unmapped, skipped)' % (n, miss))

if __name__ == '__main__':
    main()
