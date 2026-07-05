#!/usr/bin/env python3
"""Re-initialise the ethsoc picorv32 progmem (4 byte-sliced RAMB36E1 in x8
mode, READ_WIDTH_A=9) with a new firmware image, by patching the RAMB INIT_xx
params in the nextpnr JSON -- no Vivado re-synth, no re-route.

Each progmem RAMB holds one byte lane b: address W (word index) -> byte
fw[W*4 + b].  The JSON INIT_xx is a 256-char binary string, MSB-first
(char[0]=bit255), covering 32 byte-addresses (bits [j*8 +: 8] = address
line*32 + j).  The byte lane of each RAMB is AUTO-DETECTED by decoding its
current INIT and matching against the OLD firmware -- so we never hard-code
which cell is which lane, and we abort if the old image doesn't round-trip.

usage: progmem_reinit.py new_fw.bin old_fw.bin in.json out.json
"""
import json, sys

def read_bytes(p):
    b = open(p, 'rb').read()
    return b

def decode_ramb(params):
    """Return the 4096-byte content of an x8 RAMB36 from its INIT_00..7F."""
    mem = bytearray(4096)
    for line in range(128):
        s = params.get('INIT_%02X' % line)
        if s is None:
            continue
        s = s.zfill(256)
        # bit k = (s[255-k]=='1');  byte j (addr line*32+j) = bits [j*8 +: 8]
        for j in range(32):
            v = 0
            for i in range(8):
                k = j * 8 + i
                if s[255 - k] == '1':
                    v |= 1 << i
            mem[line * 32 + j] = v
    return mem

def encode_ramb(mem):
    """Return {INIT_00.. : 256-char binstr} for a 4096-byte x8 RAMB36."""
    out = {}
    for line in range(128):
        bits = ['0'] * 256
        for j in range(32):
            v = mem[line * 32 + j]
            for i in range(8):
                if (v >> i) & 1:
                    bits[255 - (j * 8 + i)] = '1'
        out['INIT_%02X' % line] = ''.join(bits)
    return out

def main():
    newfw, oldfw, jin, jout = sys.argv[1:5]
    new = read_bytes(newfw)
    old = read_bytes(oldfw)
    nwords = (len(old) + 3) // 4
    d = json.load(open(jin))

    # old firmware split into 4 byte lanes
    lanes_old = [bytes(old[b::4]) for b in range(4)]

    patched = []
    for mod in d['modules'].values():
        for name, cell in mod.get('cells', {}).items():
            if cell.get('type') != 'RAMB36E1':
                continue
            params = cell.get('parameters', {})
            if 'INIT_00' not in params:
                continue
            mem = decode_ramb(params)
            # which byte lane does this RAMB carry?  match its first nwords
            # bytes against each old lane.
            for b in range(4):
                if bytes(mem[:len(lanes_old[b])]) == lanes_old[b]:
                    # re-encode this lane with the NEW firmware
                    new_lane = bytes(new[b::4])
                    nm = bytearray(4096)
                    nm[:len(new_lane)] = new_lane
                    params.update(encode_ramb(nm))
                    patched.append((name.split('/')[-1][:30], b))
                    break

    json.dump(d, open(jout, 'w'))
    if len(patched) != 4:
        print('ERROR: expected 4 progmem byte-lane RAMBs, matched %d: %s' %
              (len(patched), patched))
        sys.exit(1)
    print('re-baked progmem lanes:', sorted(p[1] for p in patched), '->', jout)

if __name__ == '__main__':
    main()
