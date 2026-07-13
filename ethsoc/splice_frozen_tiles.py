#!/usr/bin/env python3
# Stamp golden config for frozen eth structure nextpnr can't reproduce from
# fixed-routes.  Three mechanisms:
#
# 1. CLOCK network -- TRACK-AWARE.  The eth clocks live on GCLK0-4 (rxrecclk=0,
#    userclk=1, gtrefclk=2, userclk2/eth_clk_o=3, txoutclk=4); cpu_clk=GCLK16 and
#    sysclk=GCLK17 are the CPU domain that clocks the FRESH, chip-scattered
#    arp_ctrl FFs.  routeClock rebuilds the eth clocks on wrong tracks + reversed
#    spine direction, so we REPLACE the eth-track (0-4) clock bits with golden --
#    but we KEEP nextpnr's CPU-track (>=5, i.e. 16/17) bits, because nextpnr
#    legitimately extends cpu_clk with fresh CLK_HROW taps + HCLK leaf to reach
#    the scattered arp_ctrl (wholesale replacement orphaned those -> arp_ctrl
#    never clocked -> no ARP reply).  Non-GCLK-tagged clock features (BUFHCE
#    IN_USE, ENABLE_BUFFER, HCLK leaf) are UNION (golden's eth + nextpnr's cpu).
#
# 2. BRAM -- wholesale.  nextpnr routes the RAMB36 upper/lower ADDR via fabric
#    IMUX instead of the internal CASCINTOP/CASCINBOT cascade; all 34 BRAM cells
#    are eth, so replace every BRAM_L/BRAM_R tile with golden.
#
# 3. CLB SLICES -- wholesale per stampable slice (pure-eth + Vivado route-thru;
#    fresh-cell slices are protected upstream).  Selective FF-only/popcount-only
#    splicing left LUT.INIT/DI1MUX/SRUSEDMUX/NOCLKINV gaps; a stampable slice has
#    no fresh cell, so every golden slice line is exactly correct.
#
# Usage: splice_frozen_tiles.py IN.fasm GOLD.fasm OUT.fasm [STAMPABLE_SLICES.txt]
import sys, re
infasm, goldfasm, outfasm = sys.argv[1], sys.argv[2], sys.argv[3]
pure_file = sys.argv[4] if len(sys.argv) > 4 else None

ETH_TRACKS = {0, 1, 2, 3, 4}
CLOCK_PREFIXES = (
    "CLK_BUFG_REBUF_", "CLK_BUFG_BOT_R_", "CLK_BUFG_TOP_R_",
    "CLK_HROW_BOT_R_", "CLK_HROW_TOP_R_",
    "HCLK_CMT_", "HCLK_L_", "HCLK_R_", "CLK_FEED_",
)
BRAM_PREFIXES = ("BRAM_L_", "BRAM_R_")

pure_set = set()
if pure_file:
    for l in open(pure_file):
        s = l.strip()
        if s:
            pure_set.add(s)

_gclk = re.compile(r"GCLK(\d+)")
def tile_of(line): return line.split(".", 1)[0]
def slice_of(line):
    parts = line.split(".")
    return ".".join(parts[:2]) if len(parts) >= 2 else None
def is_clock(line): return any(tile_of(line).startswith(p) for p in CLOCK_PREFIXES)
def is_bram(line):  return any(tile_of(line).startswith(p) for p in BRAM_PREFIXES)
def in_pure(line):  return slice_of(line) in pure_set
def tracks_of(line): return set(int(x) for x in _gclk.findall(line))
def clock_eth_owned(line):
    tr = tracks_of(line)
    return bool(tr) and tr <= ETH_TRACKS      # every GCLK on the line is an eth track

# --- collect golden lines by category ---------------------------------------
gold_bram = {}     # tile -> [lines]
gold_slice = {}    # slice -> [lines]
gold_clock = []    # eth-track or non-track clock lines (golden owns/contributes)
for l in open(goldfasm):
    s = l.strip()
    if not s or s.startswith("#"):
        continue
    if is_bram(s):
        gold_bram.setdefault(tile_of(s), []).append(s)
    elif in_pure(s):
        gold_slice.setdefault(slice_of(s), []).append(s)
    elif is_clock(s):
        # eth-track (GCLK0-4): golden owns (REPLACE nextpnr's reversed version).
        # cpu-track (GCLK16=cpu_clk, 17=sysclk): nextpnr OWNS -- cpu_clk is now
        # removed from the frozen routes so routeClock builds the FULL GCLK16 tree
        # natively to every sink; stamping golden's cpu backbone would diverge from
        # it (two spines from X0Y16 -> contention).  Non-track (BUFHCE/leaf enables):
        # union (golden eth-region + nextpnr cpu-region).
        tr = tracks_of(s)
        if tr and not (tr <= ETH_TRACKS):
            continue                     # cpu-track: leave to nextpnr
        gold_clock.append(s)             # eth-track or non-track
bram_keys = set(gold_bram)
slice_keys = set(gold_slice)

# --- rewrite nextpnr FASM ----------------------------------------------------
out, dropped, kept = [], 0, 0
for l in open(infasm):
    s = l.strip()
    if not s or s.startswith("#"):
        out.append(l.rstrip("\n")); continue
    if is_bram(s):
        if tile_of(s) in bram_keys:
            dropped += 1; continue            # golden replaces this BRAM tile
        out.append(s)
    elif in_pure(s):
        if slice_of(s) in slice_keys:
            dropped += 1; continue            # golden replaces this slice
        out.append(s)
    elif is_clock(s):
        if clock_eth_owned(s):
            dropped += 1; continue            # eth-track: golden provides
        out.append(s); kept += 1              # CPU-track / non-track: keep nextpnr
    else:
        out.append(s)

# --- append golden -----------------------------------------------------------
emitted = 0
for d in (gold_bram, gold_slice):
    for lines in d.values():
        out += lines; emitted += len(lines)
out += gold_clock; emitted += len(gold_clock)

# --- dedup exact-duplicate lines (clock no-track lines can appear in both) ----
seen, final = set(), []
for s in out:
    if s in seen:
        continue
    seen.add(s); final.append(s)

open(outfasm, "w").write("\n".join(final) + "\n")
print("splice_frozen_tiles: BRAM tiles=%d, slices=%d, golden-clock lines=%d; "
      "emitted=%d dropped-nextpnr=%d kept-cpu-clock=%d"
      % (len(bram_keys), len(slice_keys), len(gold_clock), emitted, dropped, kept))
