# v7-johnson-demo

A turnkey, fully open-source Virtex-7 build recipe that takes a
SystemVerilog source through synthesis, place-and-route, bitstream
assembly, and finally flashes a working bit onto a VC707 development
board.  No Vivado, no RapidWright at runtime, no proprietary device
data — pure permissive-licensed toolchain.

The headline demo is a 28-bit PRBS prescaler driving an 8-bit Johnson
counter on the VC707's 8 user LEDs, ticking at ~1 Hz.  Easy to see
working from across the room.

A second, much larger demo lives in [`uartram/`](#advanced-demo-open-flow-uart-dsp-calculator-uartram):
a UART **DSP calculator** (soft CPU + DSP48E1 + block RAM) that stress-tests the
open place-and-route + bitstream back-end on Virtex-7 hard blocks.

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

## Advanced demo: open-flow UART DSP calculator (`uartram/`)

The Johnson counter proves the flow end-to-end on a small single-clock design.
The `uartram/` directory pushes the **open-source place-and-route + bitstream
back-end** (nextpnr-xilinx + prjxray) much harder: a self-contained **32-bit
integer calculator** spoken over the VC707's USB-UART.

```
host> 40115/355=    ->   40115/355=113
host> 65535*65535=  ->   65535*65535=4294836225
host> 100-1=        ->   100-1=99
```

The design contains a small soft CPU (`calc_core` — an 8-bit accumulator machine
with its own ISA), an **explicit DSP48E1** multiply/MACC coprocessor, a
**2048×8 RAMB18** program+data memory, and a carry-free LFSR UART — roughly 970
cells. The calculator program is written in an assembler (`asm.py`, which also
simulates the ISA for self-test) and baked into the block-RAM init.

### Flow (hybrid: Vivado front-end, open back-end)
Unlike the Johnson demo, this design is **synthesised by Vivado** (its DSP/BRAM
inference and the soft CPU were simplest to drive from Vivado). Everything after
synthesis is the same fully open toolchain:

```
Vivado synth -> EDIF
  -> System-Verilog-suite  (edif_to_nextpnr.lua: EDIF -> nextpnr JSON, a reader, not a synthesiser)
  -> nextpnr-xilinx        (place + route + FASM)
  -> patch_rx_iob.py       (2-bit prjxray IOB workaround, see below)
  -> prjxray fasm2frames + xc7frames2bit  -> .bit
```

So it demonstrates the **open P&R + bitstream tools handling hard blocks**
(DSP48E1, block RAM, carry chains, single-ended HP-bank I/O) — not yet a pure-OSS
front-to-back build like the LED counter. Closing that gap (teaching SVS to
synthesise the calculator directly) is the main next step — see
[Outstanding investigations](#outstanding-investigations).

### Build / flash / test
Requires Vivado 2020.1 (synthesis only) plus the already-built open tools
(`make tools`).

```bash
cd uartram
python3 asm.py --emit          # assemble + self-test the program -> calc_init.svh
bash build_open_min.sh         # Vivado synth + open P&R + bitstream -> /tmp/uartram_min.bit
../deps/openFPGALoader/build/openFPGALoader -c digilent --freq 15M /tmp/uartram_min.bit
```

Then talk to it at **115200 8N1** on the USB-UART (`/dev/ttyUSB0`):

```bash
picocom -b 115200 /dev/ttyUSB0   # type e.g. "2+3=" ; expect "2+3=5"
```

Iterating on the *program* only (no logic change) is fast: `init_update.sh`
patches the block-RAM contents into the already-placed FASM and re-emits the bit
in seconds, skipping synthesis and P&R entirely.

### What was achieved
On the VC707 at the 156.25 MHz Si570 user clock, through the open back-end:

- **Full calculator HW-verified** — 15/15 cases incl. multi-digit output,
  subtraction, negative results, and division (`5+5=10`, `8-3=5`, `5-8=-3`,
  `40115/355=113`, full 32-bit borrow chains).
- **DSP48E1 multiply HW-verified** — 20 sign-sensitive 32×32 cases (built from
  three signed 16×16 partials): `65535²`, `32768²`, overflow wrap, etc.
- **DSP48E1 multiply-accumulate HW-verified** — 12 `P = C + A*B` cases driving
  the accumulator C-port (OPMODE `0x35`), a path the calculator itself never
  uses.

This is the first design in this flow to exercise the DSP48E1, block RAM, a soft
CPU, and bidirectional UART I/O — well beyond the LED counter.

### Outstanding investigations
- **Pure-OSS synthesis of the calculator (the main next step).** The calculator's
  netlist currently comes from Vivado. The goal is to get System-Verilog-suite
  "up to snuff" so it elaborates and gate-maps this design — DSP48E1 and RAMB18
  inference plus the soft CPU — straight to EDIF/JSON, removing the Vivado
  front-end so the calculator becomes a **100%-open front-to-back** build like the
  Johnson demo.
- **`OP_SBC` (subtract-with-borrow) is mis-compiled by the open flow.** It is the
  only ALU op with an *inverted dynamic carry-in* (`~cy`). `ADD`, `ADC`, and
  single-byte `SUB` are all bit-exact on hardware, but multi-byte `SBC` subtracts
  one too many. Root cause lies in the CARRY4 carry-in handling (nextpnr packing
  / FASM emit, or a prjxray segbit) and is **not yet fixed in the tooling**. The
  calculator works around it entirely in software: every subtract is a
  two's-complement add (`X + ~Y + 1`) using only known-good ops, so the shipped
  program emits **no `SBC` at all** (the original SBC version is preserved as
  `asm_with_sbc.py.bak`). A proper nextpnr/prjxray fix for the inverted dynamic
  CYINIT is the open item.
- **HP-bank single-ended LVCMOS18 `rx` input needs a 2-bit frame patch.** prjxray's
  Virtex-7 DB omits an input-enable bit (and sets a spurious glue bit) for the
  slave-site pin used for `rx` (AU33); `patch_rx_iob.py` sets/clears those two
  bits after `fasm2frames`. Proven by a Vivado-FASM round-trip distorting
  identically; an upstream prjxray IOB fuzz/fix is pending.
- **Timing headroom.** The calculator closes timing at 156.25 MHz (user clock)
  but not at the 200 MHz sysclk in the open flow (Fmax ≈ 150–185 MHz depending on
  placement), so it runs on the slower Si570 clock.

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
