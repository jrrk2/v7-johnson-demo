#!/usr/bin/env python3
"""Inject a program image into the ibex demo-system SRAM by patching the
RAMB36 INIT params in the SVS nextpnr JSON (then re-run the deterministic
build -> nextpnr emits INIT to FASM, no re-route needed).

The 128KiB SRAM (prim_ram_2p generic, Width=32 Depth=32768) is BIT-SLICED:
32 RAMB36E1 in width-1 (32768x1), cell u_..._mem_reg_<R>_0_<C> holds bit
N = R*8 + C of every 32-bit word.  RAMB address = (byte_addr-0x100000)/4 =
word index W; Vivado RAMB36 width-1 maps addr A -> INIT_(A>>8)[A&255].
JSON INIT param is a 256-char binary string, MSB-first (char[0]=bit255), so
mem-bit at position k sits at string index 255-k.

usage: ibex_bram_init.py prog.bin in.json out.json
"""
import json, re, sys, struct

def main():
    binf, jin, jout = sys.argv[1], sys.argv[2], sys.argv[3]
    raw = open(binf, 'rb').read()
    if len(raw) % 4:
        raw += b'\x00' * (4 - len(raw) % 4)
    words = list(struct.unpack('<%dI' % (len(raw) // 4), raw))
    nw = len(words)
    print('program: %d words (%d bytes)' % (nw, len(raw)))

    d = json.load(open(jin))
    m = max((v for v in d['modules'].values() if v.get('cells')),
            key=lambda x: len(x['cells']))
    c = m['cells']
    patched = 0
    for nm, cell in c.items():
        if 'RAMB36' not in cell['type']:
            continue
        mm = re.search(r'mem_reg_(\d+)_\d+_(\d+)$', nm)
        if not mm:
            print('WARN: RAMB cell name not recognised: %s' % nm); continue
        N = int(mm.group(1)) * 8 + int(mm.group(2))   # bit index 0..31
        params = cell.setdefault('parameters', {})
        # determine which INIT lines this program touches
        for line in range(0, (nw + 255) // 256):
            key = 'INIT_%02X' % line
            s = list('0' * 256)
            base = line * 256
            for off in range(256):
                W = base + off
                if W >= nw:
                    break
                bit = (words[W] >> N) & 1
                if bit:
                    s[255 - off] = '1'
            params[key] = ''.join(s)
        patched += 1
    json.dump(d, open(jout, 'w'))
    print('patched %d RAMB36 cells (INIT_00..INIT_%02X)' % (patched, (nw + 255) // 256 - 1))

if __name__ == '__main__':
    main()
