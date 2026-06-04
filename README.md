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
| macOS (Sequoia 15+ with Homebrew) | Secondary, validated on the cdc10134 commit branch |
| Windows | Planned, not yet supported |

## Customising / extending

- **Different design?**  Drop your `.v` and `.xdc` into a new
  directory next to `johnson/`, write a one-line `recipe.lua` (see
  `johnson/recipe.lua`), and add a Makefile target.
- **Different chip?**  Override `CHIPDB_URL` / `PART` / `CHIPDB_TAG`
  in your environment or edit the top-level Makefile.
- **Newer toolchain?**  `git submodule update --remote` then rebuild.

## Provenance / contact

This wrapper was assembled to demonstrate the end-to-end Virtex-7
open flow that came together over a multi-session collaboration
between [@jrrk2](https://github.com/jrrk2) and Anthropic Claude
during May–June 2026.  Bug reports and questions: open an issue on
this repo.
