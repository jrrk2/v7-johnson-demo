#!/usr/bin/env python3
"""Overlay golden's whole-tile config onto the frozen-macro BRAM tiles.  nextpnr
sets the BRAM ADDR mux to BRAM_IMUX (fabric) by default, but the locked golden
routing delivers the RX/TX frame-RAM address via the inter-BRAM ADDR CASCADE
(BRAM_CASCINTOP/CASCINBOT).  Config says "read fabric" while the address arrives
on the cascade -> the deep/cascaded frame RAM mis-addresses -> RX/TX corruption.
The BRAM tiles are pure-frozen (no arp_ctrl), so overlay golden's exact BRAM
config (cascade selects + width/mode/INIT) wholesale.

usage: splice_macro_bram.py in.fasm gold_bit2fasm.fasm bram_tiles.txt out.fasm
"""
import sys

def main():
    in_fasm, gold_fasm, tiles_file, out = sys.argv[1:5]
    tiles = set(l.strip() for l in open(tiles_file) if l.strip())
    def tile(line):
        return line.split('.', 1)[0] if '.' in line else None
    gold = [l.rstrip('\n') for l in open(gold_fasm) if tile(l.strip()) in tiles and l.strip() and not l.startswith('#')]
    out_lines = []
    dropped = 0
    for line in open(in_fasm):
        raw = line.rstrip('\n')
        if tile(raw) in tiles:
            dropped += 1
            continue
        out_lines.append(raw)
    out_lines.extend(gold)
    open(out, 'w').write('\n'.join(out_lines) + '\n')
    sys.stderr.write("splice_macro_bram: %d BRAM tiles, dropped %d nextpnr lines, spliced %d golden lines\n"
                     % (len(tiles), dropped, len(gold)))

if __name__ == '__main__':
    main()
