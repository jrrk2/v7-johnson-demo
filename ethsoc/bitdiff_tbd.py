#!/usr/bin/env python3
"""TBD-bits ledger: bit-level diff of an open-flow .frames file against a
golden bitread .bits dump, classified by tile.

Every difference is a To-Be-Determined bit: golden-only (we fail to set)
or ours-only (we wrongly set).  The ledger is the burn-down list for the
bit-equivalence campaign; --splice additionally writes a frames file with
all TBD bits forced to golden's values, yielding a functionally-golden
bitstream while encoder/DB fixes catch up.

usage: bitdiff_tbd.py --db-root DB --golden-bits G.bits --frames F.frames
                      [--ledger out.tsv] [--splice out.frames]
"""
import argparse, collections, json, os, sys

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db-root', required=True)
    ap.add_argument('--part-grid', default='xc7vx485t')
    ap.add_argument('--golden-bits', required=True)
    ap.add_argument('--frames', required=True)
    ap.add_argument('--ledger')
    ap.add_argument('--splice')
    a = ap.parse_args()

    tg = json.load(open(os.path.join(a.db_root, a.part_grid, 'tilegrid.json')))
    cover = collections.defaultdict(list)
    for n, t in tg.items():
        for blk, b in t.get('bits', {}).items():
            base = int(b['baseaddr'], 16)
            for f in range(b['frames']):
                cover[base + f].append((n, t['type'], b['offset'], b['words']))

    def owner(fa, w):
        for n, ty, off, words in cover.get(fa, []):
            if off <= w < off + words:
                return n, ty, off
        return None, 'UNKNOWN', 0

    gold = collections.defaultdict(set)
    for ln in open(a.golden_bits):
        p = ln.strip().split('_')
        gold[int(p[1], 16)].add((int(p[2]), int(p[3])))

    ours = collections.defaultdict(set)
    frame_words = {}
    order = []
    for ln in open(a.frames):
        ln = ln.rstrip('\n')
        if not ln:
            continue
        a_s, w_s = ln.split(' ', 1)
        fa = int(a_s, 16)
        wl = [int(x, 16) for x in w_s.split(',')]
        frame_words[fa] = wl
        order.append(fa)
        for w, v in enumerate(wl):
            for b in range(32):
                if v >> b & 1:
                    ours[fa].add((w, b))

    rows = []
    counts = collections.Counter()
    for fa in sorted(set(gold) | set(ours)):
        for direction, bits in (('G', gold[fa] - ours[fa]), ('O', ours[fa] - gold[fa])):
            for (w, b) in sorted(bits):
                tile, ty, off = owner(fa, w)
                seg = '%02d_%03d' % (fa & 0x7F, (w - off) * 32 + b) if tile else ''
                rows.append((fa, w, b, direction, tile or '-', ty, seg))
                counts[(direction, ty)] += 1

    print('TBD bits: golden-only=%d ours-only=%d' %
          (sum(v for (d, _), v in counts.items() if d == 'G'),
           sum(v for (d, _), v in counts.items() if d == 'O')))
    for (d, ty), c in counts.most_common(20):
        print('  %s %-24s %6d' % (d, ty, c))

    if a.ledger:
        with open(a.ledger, 'w') as f:
            f.write('frame\tword\tbit\tdir\ttile\ttiletype\tsegbit\n')
            for fa, w, b, d, tile, ty, seg in rows:
                f.write('0x%08X\t%d\t%d\t%s\t%s\t%s\t%s\n' % (fa, w, b, d, tile, ty, seg))
        print('ledger:', a.ledger, len(rows), 'rows')

    if a.splice:
        # force golden values on every TBD bit
        for fa, w, b, d, tile, ty, seg in rows:
            if fa not in frame_words:
                frame_words[fa] = [0] * 101
                order.append(fa)
            if d == 'G':
                frame_words[fa][w] |= (1 << b)
            else:
                frame_words[fa][w] &= ~(1 << b)
        with open(a.splice, 'w') as f:
            for fa in sorted(frame_words):
                f.write('0x%08X ' % fa +
                        ','.join('0x%08X' % x for x in frame_words[fa]) + '\n')
        print('splice frames:', a.splice)

if __name__ == '__main__':
    main()
