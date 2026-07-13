# blessed_routes — HW-verified frame config for prjxray-incomplete tiles

The open (R0) flow imports golden's **placement** and re-routes with nextpnr,
then encodes with prjxray's virtex7 DB. A handful of "hard" tiles are
incompletely fuzzed in that DB (`bits:{}` or self-consistent-but-wrong
segbits), so fasm2frames cannot encode the design's routing through them:

| tile class            | symptom on the Ibex open-flow bit         |
|-----------------------|-------------------------------------------|
| `CFG_CENTER_MID`      | BSCAN/riscv-dbg dead — `dtmcs` reads -1    |
| `CMT_TOP` / `HCLK_CMT`| MMCM won't lock — `clk_sys` dead, CPU held |
| `LIOB18_SING`, HP IOB | led[4] / single-ended I/O dead            |
| `GTX` (tilegrid empty)| SGMII unbuildable                          |

Because the placement is golden's, a reference's config for a **fixed tile**
(same BEL site) is reusable by any design that lands the hard block there. So
we cache a known-good encoding lifted from a reference bitstream and splice it
into the design's frames after fasm2frames.

## Trust model

An entry is only **`verified: "hw"`** once the *source* bitstream was confirmed
running on real hardware. `"sim"` = matches a golden Vivado bit but not yet
HW-confirmed in this context. `"none"` = extracted, untrusted.

- `mmcm_clkin` — CMT/MMCM + 200 MHz clock-input route, lifted from the
  **HW-working** open-flow loopback (`/tmp/lb_r0.bit`, which shows a live
  `clk_sys` heartbeat + UART loopback over JTAG). `verified: hw`.
- `cfg_center_bscan` — BSCAN routing, from the golden Vivado bit. Took the Ibex
  `dtmcs` from -1 (dead) to responding; `verified: sim`.

## Usage

```sh
# extract an entry from a reference bit over given frame ranges
python3 bless.py extract <ref.bit> <id> replace|add <lo:hi> ...

# splice all (or named) entries into a design's frames, post-fasm2frames
python3 bless.py apply  design.frames  out.frames  [id ...]

python3 bless.py list           # show the manifest with provenance + trust
```

Wire `apply` into `build_ibex_edif_r0.sh` between `patch_bscan.py` and
`xc7frames2bit`. Entries are **placement-keyed** — re-extract after any
re-synth that moves the hard blocks (the `placement_key` field records where
the entry is valid).

## Modes

- `replace` — set the listed frames to exactly the reference's 101-word values
  (removes the design's wrong bits *and* adds the reference's). Use for tiles
  where the design emits conflicting bits (CFG_CENTER, CMT).
- `add` — OR the reference's set-bits into the design frames (like
  `patch_bscan.py` / `patch_led4_iob.py`). Use for pure gaps (missing enables).
