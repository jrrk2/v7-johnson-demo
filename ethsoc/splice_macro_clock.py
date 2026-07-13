#!/usr/bin/env python3
# Wholesale-stamp the golden CLOCK NETWORK (spine + leaf) into the open-flow FASM.
#
# Why: nextpnr's routeClock rebuilds the eth clock nets (txoutclk/userclk2/gtrefclk)
# on its own GCLK tracks + REVERSED spine direction (GCLKn_TOP.GCLKn_BOT), and adds
# spurious sysclk/cpu clocks on GCLK23/GCLK4.  The golden eth-clock distribution
# (GCLK16/17, BOT->TOP, correct BUFGCTRL sources) never lands -> the 125MHz SGMII
# domain never clocks on silicon (no link/sync LEDs).  Every eth clock SOURCE
# (MMCME2_X0Y3, BUFGCTRL_X0Y0-4, GTXE2_COMMON_X1Y0) and every eth clock SINK are
# frozen at golden sites, so the golden clock-tile bits are exactly correct.  Stamp
# them verbatim, dropping nextpnr's conflicting clock-tile lines.
#
# Spine + leaf clock tiles are REPLACED (not unioned): opposite-direction spine pips
# in one tile would short.  The fresh board/cpu clock (sysclk->cpu_mmcm->arp_ctrl on
# GCLK23) is intentionally dropped here -- that domain is handled separately; this
# splice's job is to make the eth 125MHz domain propagate.
import sys

infasm, goldfasm, outfasm = sys.argv[1], sys.argv[2], sys.argv[3]

# Tile-NAME prefixes whose lines are owned entirely by the golden clock network.
CLK_PREFIXES = (
    "CLK_BUFG_REBUF_",
    "CLK_BUFG_BOT_R_", "CLK_BUFG_TOP_R_",
    "CLK_HROW_BOT_R_", "CLK_HROW_TOP_R_",
    "HCLK_CMT_",
    "HCLK_L_", "HCLK_R_",
    "CLK_FEED_",
)

def tile_of(line):
    return line.split(".", 1)[0]

def is_clk(line):
    t = tile_of(line)
    return any(t.startswith(p) for p in CLK_PREFIXES)

# Collect golden clock lines, grouped by tile (preserve order).
gold_clk = {}
for l in open(goldfasm):
    s = l.strip()
    if not s or s.startswith("#"):
        continue
    if is_clk(s):
        gold_clk.setdefault(tile_of(s), []).append(s)

gold_tiles = set(gold_clk)

# Rewrite: drop nextpnr lines in any clock tile the golden network touches;
# keep nextpnr clock lines in tiles golden doesn't touch (harmless empties).
dropped = 0
kept_clk = 0
out = []
seen_gold_emit = set()
for l in open(infasm):
    s = l.strip()
    if not s or s.startswith("#"):
        out.append(l.rstrip("\n"))
        continue
    if is_clk(s):
        t = tile_of(s)
        if t in gold_tiles:
            dropped += 1          # nextpnr's version discarded; golden emitted below
            continue
        else:
            kept_clk += 1
            out.append(s)
    else:
        out.append(s)

# Append the full golden clock network.
emitted = 0
for t in sorted(gold_clk):
    for s in gold_clk[t]:
        out.append(s)
        emitted += 1

with open(outfasm, "w") as f:
    f.write("\n".join(out) + "\n")

print("splice_macro_clock: golden clock tiles=%d, emitted %d golden lines, "
      "dropped %d nextpnr clock lines (kept %d nextpnr clock lines in untouched tiles)"
      % (len(gold_tiles), emitted, dropped, kept_clk))
