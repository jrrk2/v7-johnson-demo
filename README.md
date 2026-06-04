# v7-johnson-demo

A turnkey, fully open-source Virtex-7 build recipe that takes a
SystemVerilog source through synthesis, place-and-route, bitstream
assembly, and finally flashes a working bit onto a VC707 development
board.  No Vivado, no RapidWright at runtime, no proprietary device
data — pure permissive-licensed toolchain.

The demo design is a 28-bit PRBS prescaler driving an 8-bit Johnson
counter on the VC707's 8 user LEDs, ticking at ~1 Hz.  Easy to see
working from across the room.

## Quick start

```bash
git clone --recursive https://github.com/jrrk2/v7-johnson-demo
cd v7-johnson-demo
make deps     # one-time: install OS packages (apt or brew)
make          # build all tools + chipdb + demo bit
make flash    # write counter28.bit to a VC707 over JTAG
```

That's it.  On a clean Ubuntu 24.04 box with the VC707 plugged in,
`make` takes about 15 minutes the first time (mostly compiling
nextpnr-xilinx and System-Verilog-suite) and a few seconds for
subsequent incremental rebuilds.

## What's in the toolchain

| Component | Repo | Role |
|---|---|---|
| `deps/System-Verilog-suite` | [jrrk2/System-Verilog-suite](https://github.com/jrrk2/System-Verilog-suite) | SV elaboration + Hardcaml-backed gate mapping |
| `deps/nextpnr-xilinx` | [openXC7/nextpnr-xilinx](https://github.com/openXC7/nextpnr-xilinx) (branch `virtex7-support`) | Place + route + FASM emit |
| `deps/prjxray` | [openXC7/prjxray](https://github.com/openXC7/prjxray) (branch `virtex7-support`) | FASM → frames → .bit |
| `deps/openFPGALoader` | [trabucayre/openFPGALoader](https://github.com/trabucayre/openFPGALoader) | JTAG flash via FTDI/Digilent cable |
| `deps/...chipdb...` | openXC7 release `chipdb-2026-06-03` | Pre-built chip database (~150 MB) |

The chipdb is fetched as a release asset rather than rebuilt from
RapidWright DeviceResources — that keeps the build pure-OSS and
avoids the ~200 MB RapidWright jar.

## Make targets

| Target | What |
|---|---|
| `make`              | Build everything: deps init, tools, chipdb, demo .bit |
| `make deps`         | Install OS packages (sudo apt or brew) |
| `make tools`        | Build the toolchain (no bit) |
| `make johnson.bit`  | Just the demo bit (assumes tools built) |
| `make flash`        | Flash counter28.bit to a connected VC707 |
| `make clean`        | Remove build dirs + intermediates; keep cloned deps |
| `make distclean`    | Also remove cloned deps + chipdb |

## Demo design

`johnson/counter25_core.v` implements:

```
200 MHz LVDS sysclk -> IBUFDS -> BUFG -> clk
  prbs    : 28-bit LFSR (x^28 + x^3 + 1)
  tick    : prbs == 28'h1                    (every ~2^28 cycles ~ 1 Hz)
  johnson : 8-bit twisted-ring, advances on tick -> led[7:0]
```

`top.v` wraps the core with the IBUFDS/BUFG/IBUF/8x OBUF primitives the
flow needs at the VC707's IO pad.  `top.xdc` pins everything to the
board's documented sysclk_p/sysclk_n, CPU_RESET, and GPIO_LED_0..7.

## Supported platforms

| OS | Status |
|---|---|
| Linux (Ubuntu 24.04, Debian 12) | Primary, fully tested |
| macOS (Sequoia 15+ with Homebrew) | Secondary; builds a working bit, but **not** bit-identical to Linux — see [Limitations](#limitations-and-caveats) |
| Windows | Planned, not yet supported |

## Limitations and caveats

This is a **demonstration** that a fully open-source Virtex-7 flow can take
SystemVerilog all the way to a working bitstream — not a production-hardened
toolchain. The flow is real and the bit genuinely runs on hardware, but there
are sharp edges worth understanding before you build your own designs on it.

### The build can silently produce a non-working bitstream
Two environment flags in the place-and-route / FASM steps trade correctness
guarantees for "always emit an output":

- **`NEXTPNR_SKIP_FAILED_ARCS=1`** — if `router1` can't route a net within its
  visit budget it *drops the connection* instead of failing. High-fanout
  constant nets (`$PACKER_VCC_NET`) are the usual casualties on congested
  placements.
- **`XRAY_ALLOW_MISSING_FEATURES=1`** — if a FASM feature isn't in the prjxray
  database, `fasm2frames` *omits those bits* instead of erroring (see DB gaps
  below).

Both convert "I can't do this correctly" into "emit a bitstream with missing
bits." The board can program successfully (`DONE` goes high) yet not function.
If you adapt this flow for real work, consider turning these off so failures
are loud rather than silent.

### Results are placement-sensitive
Because of the above, whether a design builds *correctly* can depend on the
placement nextpnr happens to land on — a more congested placement can tip
`router1` over its congestion cliff and start dropping arcs. The demo is small
enough to route cleanly, but the headroom is limited. For anything larger,
switching to `--router router2` (negotiated-congestion) is the recommended
path and is far more robust with high-fanout const nets.

### Cross-platform reproducibility is only partial
The analytic placer was made deterministic and identical across C++ standard
libraries (nextpnr commit `1863fa0e`: shuffle with `std::mt19937` over a
name-sorted bel-type order, replacing the implementation-defined
`std::default_random_engine` that made libstdc++ and libc++ diverge). However,
the placer's *parallel Eigen floating-point solve* still depends on thread
count and CPU architecture. **Linux (x86) and macOS (especially Apple Silicon)
therefore produce working but not bit-identical bitstreams.** For bit-exact
reproducibility across machines, force the placer single-threaded
(`OMP_NUM_THREADS=1`, or `Eigen::setNbThreads(1)` in the placer).

### The device database has gaps
The prjxray Virtex-7 database does not document every tile feature. Notably the
left-edge I/O (`LIOI`) OLOGIC/ILOGIC route-thru segbits are missing, so every
build emits ~27 `… not found` warnings whose bits are silently dropped —
tolerated here only because they happen to be benign for this design's
clocking. A design that genuinely relied on those resources would
mis-configure.

### Narrow validation surface
- **One device:** `xc7vx485tffg1761-2` only. Other Virtex-7 parts need a
  different chipdb + prjxray DB and are untested.
- **One board:** the Xilinx VC707. `top.xdc` pin constraints are board-specific.
- **One design class:** a single-clock LED counter. No multi-clock domains,
  MMCM/PLL, SERDES, high-speed I/O, or external memory have been exercised.
- **Timing:** the validated build passes at 200 MHz, but a residual
  silicon-level rate glitch on V7 OLOGIC pads (noted in the design comments)
  is not fully characterised.

### Prebuilt chipdb
The chip database is downloaded as a release asset, not regenerated from
RapidWright DeviceResources in-tree. This keeps the build pure-OSS and fast,
but you are trusting the published artifact rather than reproducing it from
source.

## Customising / extending

- **Different design?**  Drop your `.v` and `.xdc` into a new
  directory next to `johnson/`, write a one-line `recipe.lua` (see
  `johnson/recipe.lua`), and add a Makefile target.
- **Different chip?**  Override `CHIPDB_URL` / `PART` / `CHIPDB_TAG`
  in your environment or edit the top-level Makefile.
- **Newer toolchain?**  `git submodule update --remote` then rebuild.
- **Want to push to one of the submodules?**  All remotes are
  HTTPS-by-default so anonymous clones work without an SSH key.  If
  you have push rights to one of the upstreams, add an
  `insteadOf` rewrite to your **global** git config — it transparently
  swaps the URL on `git fetch` / `git push` without you having to
  touch the wrapper repo or its `.gitmodules`.  Example:
  ```bash
  git config --global \
    url."git@github.com:openXC7/".insteadOf "https://github.com/openXC7/"
  git config --global \
    url."git@github.com:jrrk2/".insteadOf "https://github.com/jrrk2/"
  ```
  Anyone else's clone continues to use HTTPS; only your local
  fetches/pushes get the rewrite.

## Provenance / contact

This wrapper was assembled to demonstrate the end-to-end Virtex-7
open flow that came together over a multi-session collaboration
between [@jrrk2](https://github.com/jrrk2) and Anthropic Claude
during May–June 2026.  Bug reports and questions: open an issue on
this repo.
