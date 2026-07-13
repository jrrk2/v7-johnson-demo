#!/usr/bin/env python3
"""Decode a pip-fuzz bitstream: for each forced suspect pip, extract the
target INT tile's set bits from the bitstream, subtract the db-predicted
bits of every OTHER pip in that tile (from the Vivado pip dump), and print
the suspect pip's TRUE bits next to the prjxray segbits prediction.

usage: pipfuzz_decode.py <prefix>   (expects <prefix>.bit and <prefix>_pips.txt)
"""
import sys, re, json, subprocess, collections, os

DBDIR   = os.path.expanduser("~/prjxray/database/virtex7")
TILEGRID= "/home/jonathan/v7-johnson-demo/deps/prjxray/database/virtex7/xc7vx485t/tilegrid.json"
BITREAD = os.path.expanduser("~/prjxray/build/tools/bitread")
PARTYAML= f"{DBDIR}/xc7vx485tffg1761-2/part.yaml"

pref = sys.argv[1]

# ---- 1. bitstream -> set bits ----
bits_path = f"/tmp/{os.path.basename(pref)}.bits"
subprocess.run([BITREAD, "--part_file", PARTYAML, "-o", bits_path, pref + ".bit"],
               check=True, capture_output=True)
frames = {}
frame = None; word = 0
for ln in open(bits_path):
    ln = ln.strip()
    if ln.startswith(".frame"):
        frame = int(ln.split()[1], 16); word = 0; frames.setdefault(frame, {})
        continue
    if not ln or frame is None: continue
    for w in ln.split():
        v = int(w, 16)
        if v: frames[frame][word] = v
        word += 1

grid = json.load(open(TILEGRID))

def tile_setbits(tile):
    b = grid[tile]["bits"]["CLB_IO_CLK"]
    base = int(b["baseaddr"], 16); off = b["offset"]; nw = b["words"]; nf = b["frames"]
    out = set()
    for fi in range(nf):
        fw = frames.get(base + fi, {})
        for wi in range(off, off + nw):
            v = fw.get(wi, 0)
            for bit in range(32):
                if v >> bit & 1:
                    out.add((fi, (wi - off) * 32 + bit))   # (minor, tilebit)
    return out

# ---- 2. segbits db ----
def load_segbits():
    db = {}
    for tt in ("int_l", "int_r"):
        for ln in open(f"{DBDIR}/segbits_{tt}.db"):
            p = ln.split()
            pos = frozenset(tuple(map(int, b.split("_"))) for b in p[1:] if not b.startswith("!"))
            neg = frozenset(tuple(map(int, b.split("_"))) for b in p[1:] if b.startswith("!")
                            for b in [b[1:]])
            db.setdefault(p[0], []).append((pos, neg))
    return db
segbits = load_segbits()

def db_bits(ptype):
    """positive bits of a feature (first entry)."""
    e = segbits.get(ptype)
    return set(e[0][0]) if e else None

# ---- 3. per-net pip dump ----
forced = {}         # netname -> (ptype, tile)
tilepips = collections.defaultdict(list)   # tile -> [(net, fasmtype)]
for ln in open(pref + "_pips.txt"):
    p = ln.split()
    if p[0] == "NET":
        print(" ".join(p))
        if p[2] == "FORCED": forced[p[1]] = (p[3], p[4])
    elif p[0] == "PIP":
        net, pip = p[1], p[2]
        tile, rest = pip.split("/")
        if not tile.startswith(("INT_L", "INT_R")): continue
        m = re.match(r'([A-Z_0-9]+)\.(\S+?)(->>|<<->>|->)(\S+)$', rest)
        if not m: continue
        tt, a, arrow, b = m.groups()
        # Vivado: SRC->>DST ; FASM: TILETYPE.DST.SRC
        ftype = f"{tt}.{b}.{a}"
        tilepips[tile].append((net, ftype, f"{tt}.{a}.{b}"))

# ---- 4. per suspect: measured - known ----
print("\n=== RESULTS ===")
for net, (ptype, tile) in forced.items():
    meas = tile_setbits(tile)
    known = set(); unknown_others = []
    others = [x for x in tilepips.get(tile, []) if x[1] != ptype and x[2] != ptype]
    for onet, ft, ftrev in others:
        b = db_bits(ft) or db_bits(ftrev)
        if b is None: unknown_others.append(ft)
        else: known |= b
    residual = meas - known
    pred = db_bits(ptype)
    print(f"\n{ptype} @ {tile}  (net {net})")
    print(f"  measured tile bits : {sorted(meas)}")
    print(f"  other pips there   : {[x[1] for x in others]}"
          + (f"  UNKNOWN: {unknown_others}" if unknown_others else ""))
    print(f"  residual (=suspect): {sorted(residual)}")
    print(f"  db prediction      : {sorted(pred) if pred else 'NO ENTRY'}")
    if pred is not None:
        verdict = "MATCH" if residual == set(pred) else "MISMATCH"
        print(f"  --> {verdict}")
