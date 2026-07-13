#!/usr/bin/env python3
"""Blessed-routes cache: a persistent, HW-verified store of frame-level
config for the prjxray-INCOMPLETE "hard" tiles (clock-input route, CMT/MMCM,
CFG_CENTER/BSCAN, single-ended HP IOBs, GT).  prjxray's virtex7 DB either has
`bits:{}` (no frame definition) or self-consistent-but-wrong segbits for these
tiles, so fasm2frames cannot encode the open-flow design's own routing through
them.  Rather than re-derive (and fail), the R0 flow splices in a known-good
encoding lifted from a reference bitstream (golden Vivado, or an HW-verified
open-flow design like the loopback) for the matching tiles.

WHY this is sound: the R0 flow imports the golden PLACEMENT, so a reference's
config for a fixed tile (same BEL location) is directly reusable by any design
that lands the hard block there.  An entry is only "blessed" (verified:"hw")
once the source bit was confirmed working on real hardware.

Entry file  blessed_routes/<id>.json:
  { "id": str, "placement_key": str, "mode": "add"|"replace",
    "frame_ranges": [[lo,hi],...],          # informational / for re-extract
    # mode "add":      OR these bits into the design frames (like patch_bscan)
    "set_bits":  { "0xADDR": [[word,bit],...], ... },
    # mode "replace":  set these frames to exactly these 101-word values
    "frames":    { "0xADDR": [w0..w100], ... },
    "source": str, "verified": "hw"|"sim"|"none", "note": str }

Subcommands:
  extract <ref.bit> <id> <mode> <lo:hi>...   bitread ref over ranges -> entry
  apply   <in.frames> <out.frames> [id...]   splice listed entries (default: all)
  list                                       show the manifest

Frame file format (fasm2frames / xc7frames2bit): lines "0xADDR w0,w1,...,w100".
"""
import sys, os, re, json, subprocess, collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BITREAD = os.path.join(ROOT, "deps/prjxray/build/tools/bitread")
PARTYAML = os.path.join(ROOT, "deps/prjxray/database/virtex7/xc7vx485tffg1761-2/part.yaml")


def _bitread(bitfile, lo, hi):
    """Return {frame_addr:int -> [(word,bit)...]} of set bits in [lo,hi]."""
    out = "/tmp/_bless_%d_%d.bits" % (lo, hi)
    if os.path.exists(out):
        os.remove(out)
    # bitread exits non-zero even on success; rely on the output file instead.
    subprocess.run([BITREAD, "--part_file", PARTYAML, "-F",
                    "0x%08X:0x%08X" % (lo, hi), "-o", out, "-z", "-y", bitfile],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not os.path.exists(out):
        raise RuntimeError("bitread produced no output for %s [%x:%x]" % (bitfile, lo, hi))
    bits = collections.defaultdict(list)
    for ln in open(out):
        m = re.match(r"bit_([0-9a-f]+)_(\d+)_(\d+)", ln.strip())
        if m:
            bits[int(m.group(1), 16)].append((int(m.group(2)), int(m.group(3))))
    return bits


def extract(ref, eid, mode, ranges):
    rngs = []
    for r in ranges:
        lo, hi = (int(x, 16) for x in r.split(":"))
        rngs.append([lo, hi])
    entry = {"id": eid, "placement_key": eid, "mode": mode,
             "frame_ranges": rngs, "source": os.path.basename(ref),
             "verified": "none", "note": ""}
    if mode == "add":
        sb = {}
        for lo, hi in rngs:
            for a, wbs in _bitread(ref, lo, hi).items():
                sb["0x%08X" % a] = sorted(wbs)
        entry["set_bits"] = sb
        n = sum(len(v) for v in sb.values())
    else:  # replace: store full 101-word frames reconstructed from set bits
        fr = {}
        for lo, hi in rngs:
            bits = _bitread(ref, lo, hi)
            for a in range(lo, hi + 1):
                words = [0] * 101
                for w, b in bits.get(a, []):
                    words[w] |= 1 << b
                fr["0x%08X" % a] = words
        entry["frames"] = fr
        n = len(fr)
    json.dump(entry, open(os.path.join(HERE, eid + ".json"), "w"), indent=1)
    print("extracted '%s' (%s, %d %s) from %s" %
          (eid, mode, n, "bits" if mode == "add" else "frames", entry["source"]))


def _load_entries(ids):
    ents = []
    for fn in sorted(os.listdir(HERE)):
        if fn.endswith(".json") and fn != "MANIFEST.json":
            e = json.load(open(os.path.join(HERE, fn)))
            if not ids or e["id"] in ids:
                ents.append(e)
    return ents


def apply(infr, outfr, ids):
    ents = _load_entries(ids)
    add = {}      # addr -> set of (word,bit)
    repl = {}     # addr -> [words]
    for e in ents:
        if e["mode"] == "add":
            for a, wbs in e.get("set_bits", {}).items():
                add.setdefault(int(a, 16), set()).update(map(tuple, wbs))
        else:
            for a, w in e.get("frames", {}).items():
                repl[int(a, 16)] = w
    out = []
    for ln in open(infr):
        ln = ln.rstrip("\n")
        ad = ln.split(" ", 1)[0]
        try:
            a = int(ad, 16)
        except ValueError:
            out.append(ln); continue
        if a in repl:
            out.append("%s %s" % (ad, ",".join("0x%08X" % w for w in repl[a])))
        elif a in add:
            w = [int(x, 16) for x in ln.split(" ", 1)[1].split(",")]
            for wi, bi in add[a]:
                w[wi] |= 1 << bi
            out.append("%s %s" % (ad, ",".join("0x%08X" % x for x in w)))
        else:
            out.append(ln)
    open(outfr, "w").write("\n".join(out) + "\n")
    print("applied %d entries (%s); replace=%d frames, add=%d frames" %
          (len(ents), ",".join(e["id"] for e in ents), len(repl), len(add)))


def manifest():
    for e in _load_entries(None):
        print(" %-22s mode=%-7s verified=%-4s src=%-26s %s" %
              (e["id"], e["mode"], e["verified"], e["source"], e.get("note", "")))


def main():
    if len(sys.argv) < 2:
        print(__doc__); return
    cmd = sys.argv[1]
    if cmd == "extract":
        extract(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:])
    elif cmd == "apply":
        apply(sys.argv[2], sys.argv[3], sys.argv[4:])
    elif cmd == "list":
        manifest()
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
