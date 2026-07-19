# v7-johnson-demo — top-level Makefile
#
# Build the full Virtex-7 open-flow toolchain from source, fetch the
# pre-built chipdb, run the slowed Johnson-counter demo through it,
# flash to a VC707.  Tested on Linux (Ubuntu 24.04) and macOS (15+).
#
#   make                build everything + the .bit
#   make deps           install OS packages (sudo apt / brew)
#   make tools          build all in-tree tools (no flashing, no install)
#   make johnson.bit    just the demo bit (assumes tools are already built)
#   make picosoc        build the open-flow PicoSoC bit (needs riscv-gcc)
#   make flash          flash the latest bit to the VC707 over JTAG
#   make clean          remove all build artefacts (keeps cloned deps)
#   make distclean      also remove cloned deps + chipdb (start over)

SHELL          := /bin/bash
.SHELLFLAGS    := -eu -o pipefail -c
.DEFAULT_GOAL  := all
MAKEFLAGS      += --no-print-directory

ROOT           := $(CURDIR)
DEPS           := $(ROOT)/deps
BUILD          := $(ROOT)/build
DEMO           := $(ROOT)/johnson

# Detect platform — apt vs brew choose at deps target.
UNAME_S        := $(shell uname -s)

# nextpnr links Boost::Python, whose ABI is tied to one exact CPython minor
# version.  Distro Boost (libboost_pythonNNN) is built against the *system*
# python, but a `python3` earlier on PATH (e.g. a conda env) is often a
# different minor with no matching Boost component — cmake then fails with
# "No version of Boost::Python 3.x could be found".  On Linux, read the
# version baked into the installed libboost_python and pin everything to the
# matching interpreter so the venv and Boost::Python stay ABI-consistent.
ifeq ($(UNAME_S),Linux)
BOOST_PY_VER   := $(shell ls /usr/lib/*/libboost_python3*.so 2>/dev/null | \
                    grep -oE 'python3[0-9]+' | head -1 | \
                    sed -E 's/python3([0-9]+)/3.\1/')
SYS_PYTHON     := $(if $(BOOST_PY_VER),$(shell command -v python$(BOOST_PY_VER) 2>/dev/null))
endif

# Where each tool lives after `git submodule update --init`.
NEXTPNR_DIR    := $(DEPS)/nextpnr-xilinx
PRJXRAY_DIR    := $(DEPS)/prjxray
OPENFLD_DIR    := $(DEPS)/openFPGALoader

# Device database (segbits/tilegrid) AND the derived chipdb now come from
# ONE synchronized openXC7/database-virtex7 release, so they can never drift
# (the old setup pulled them from two tool-fork repos with separate dates).
# The chipdb (xc7vx485t.bin.zst, fetched + decompressed to the plain .bin
# nextpnr expects) is built from this exact DB; its .bba format is tied to the
# nextpnr-xilinx commit in the release manifest.json — keep deps/nextpnr-xilinx
# on that commit.  Bump DEVICE_DB_TAG to adopt a newer release.
DEVICE_DB_TAG  := device-db-2026-07-14
DEVICE_DB_REL  := https://github.com/openXC7/database-virtex7/releases/download/$(DEVICE_DB_TAG)

CHIPDB_TAG     := $(DEVICE_DB_TAG)
CHIPDB_URL     := $(DEVICE_DB_REL)/xc7vx485t.bin.zst
CHIPDB         := $(NEXTPNR_DIR)/xilinx/xc7vx485t.bin

PRJXRAY_DB_TAG := $(DEVICE_DB_TAG)
PRJXRAY_DB_URL := $(DEVICE_DB_REL)/prjxray-database-virtex7.tar.zst
PRJXRAY_DB_TAR := $(BUILD)/$(DEVICE_DB_TAG).tar.zst
# Sentinel file that proves the DB tarball has been extracted.
PRJXRAY_DB_OK  := $(PRJXRAY_DIR)/database/virtex7/xc7vx485tffg1761-2/part.yaml

# Cargo of tool binaries the demo step consumes.
NEXTPNR_BIN    := $(NEXTPNR_DIR)/build/nextpnr-xilinx
OFL_BIN        := $(OPENFLD_DIR)/build/openFPGALoader
# Stock yosys (no plugin) synthesises all three demos straight from
# (System)Verilog — installed by `make deps`, not built here.  Override to your
# install; auto-discovers oss-cad-suite / an OpenROAD build / PATH.
YOSYS          ?= $(firstword $(wildcard $(HOME)/oss-cad-suite/bin/yosys \
                    $(HOME)/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys) yosys)
FASM2FRAMES    := $(PRJXRAY_DIR)/utils/fasm2frames.py
FRAMES2BIT     := $(PRJXRAY_DIR)/build/tools/xc7frames2bit
PRJXRAY_DB     := $(PRJXRAY_DIR)/database/virtex7

# Project X-Ray's Python tools (fasm2frames) run from a self-contained
# venv built from prjxray's requirements.txt — which installs prjxray,
# fasm and python-sdf-timing editable from the in-tree submodules.  This
# isolates the build from any prjxray installed elsewhere on the system.
# Override PYTHON to pick the interpreter the venv is created from.  On Linux
# default to the Boost-matched system python (see SYS_PYTHON above) so the venv
# and nextpnr's Boost::Python agree; fall back to plain python3 elsewhere.
PYTHON         ?= $(or $(SYS_PYTHON),python3)
PRJXRAY_VENV   := $(PRJXRAY_DIR)/env
PRJXRAY_PY     := $(PRJXRAY_VENV)/bin/python
# Regular-file stamp used as the make target: env/bin/python is a symlink
# to the interpreter, so make would follow it to that binary's (old)
# mtime and rebuild the venv every run.
PRJXRAY_STAMP  := $(PRJXRAY_VENV)/.installed

# Demo design + intermediate artefacts.
PART           := xc7vx485tffg1761-2
DEMO_BIT       := $(DEMO)/counter28.bit
DEMO_FASM      := $(DEMO)/counter28.fasm
DEMO_FRAMES    := $(DEMO)/counter28.frames
DEMO_JSON      := $(DEMO)/top.json

# Second example: the telegraph (repeating bit-banged UART).  Same flow,
# its own source directory + artefacts.
TG_DIR         := $(ROOT)/telegraph
TG_BIT         := $(TG_DIR)/telegraph.bit
TG_FASM        := $(TG_DIR)/telegraph.fasm
TG_FRAMES      := $(TG_DIR)/telegraph.frames
TG_JSON        := $(TG_DIR)/top.json


# ─── high-level targets ────────────────────────────────────────────────

.PHONY: all deps tools chipdb johnson.bit telegraph telegraph.bit flash telegraph-flash calc calc.bit calc-flash picosoc picosoc-flash clean distclean help svs-tools svs_arp svs_arp-flash svs_arp_synth svs_arp_synth-sta svs_arp_synth-timing svs_arp_synth-flash svs_hybrids svs_hybrid_ethmacro svs_hybrid_sgmii svs_hybrid_framing svs_hybrid_arp svs_diag

# Keep intermediates even if a recipe exits non-zero (the telegraph route
# step does, on its skipped don't-care CARRY4.S arcs + timing miss; the calc
# fasm is kept if a seed misses 200 MHz so you can inspect/retry).
.PRECIOUS: $(TG_FASM) $(TG_FRAMES) $(DEMO_FASM) $(DEMO_FRAMES) $(CALC_FASM) $(CALC_FRAMES)

all: $(DEMO_BIT)
	@echo
	@echo "=== Build complete ==="
	@echo "Bit: $(DEMO_BIT)"
	@echo "Flash with: make flash"

help:
	@sed -n 's/^# //p; /^\.PHONY/q' $(firstword $(MAKEFILE_LIST))

tools: $(NEXTPNR_BIN) $(OFL_BIN) $(FRAMES2BIT) $(CHIPDB) $(PRJXRAY_DB_OK)
	@echo "All tools built and chipdb + prjxray DB fetched."

johnson.bit: $(DEMO_BIT)

telegraph: $(TG_BIT)
telegraph.bit: $(TG_BIT)

flash: $(DEMO_BIT) | $(OFL_BIN)
	$(OFL_BIN) --cable digilent --freq 15000000 $(DEMO_BIT)

telegraph-flash: $(TG_BIT) | $(OFL_BIN)
	$(OFL_BIN) --cable digilent --freq 15000000 $(TG_BIT)


# ─── OS package install ────────────────────────────────────────────────

deps:
ifeq ($(UNAME_S),Linux)
	@scripts/deps-linux.sh
else ifeq ($(UNAME_S),Darwin)
	@scripts/deps-macos.sh
else
	@echo "Unsupported OS: $(UNAME_S).  Windows is planned, not supported." >&2
	@exit 1
endif


# ─── submodule init ────────────────────────────────────────────────────

$(DEPS)/.initialised:
	git submodule update --init --recursive
	@touch $@


# ─── chipdb download (openXC7 release, ~150 MB) ────────────────────────

chipdb: $(CHIPDB)

$(CHIPDB): | $(DEPS)/.initialised
	@mkdir -p $(dir $@)
	@if [ ! -s $@ ]; then \
	   echo "Fetching chipdb $(CHIPDB_TAG)..."; \
	   curl -fL -o $@.zst $(CHIPDB_URL); \
	   zstd -df $@.zst -o $@; \
	   rm -f $@.zst; \
	fi


# ─── prjxray virtex7 fuzzer DB (openXC7 release, ~1.6 MB compressed) ──

prjxray-db: $(PRJXRAY_DB_OK)

$(PRJXRAY_DB_TAR): | $(DEPS)/.initialised
	@mkdir -p $(dir $@)
	@echo "Fetching prjxray virtex7 DB $(PRJXRAY_DB_TAG)..."
	curl -fL -o $@ $(PRJXRAY_DB_URL)

$(PRJXRAY_DB_OK): $(PRJXRAY_DB_TAR)
	@echo "Extracting prjxray virtex7 DB..."
	@mkdir -p $(PRJXRAY_DIR)/database
	cd $(PRJXRAY_DIR)/database && \
	    tar --use-compress-program='zstd -d --long=27' -xf $(PRJXRAY_DB_TAR)
	@test -s $@ || { echo "prjxray DB extract failed -- part.yaml missing" >&2; exit 1; }
	@# tar restores the archive's stored mtimes, so the extracted part.yaml
	@# is older than the downloaded tarball and make would re-extract every
	@# run.  Bump its mtime so it registers as up to date against the tar.
	@touch $@


# ─── nextpnr-xilinx ────────────────────────────────────────────────────

# nextpnr-xilinx hardcodes a bare `-fopenmp` in its Release flags (to
# accelerate the analytic placer).  On macOS the default /usr/bin/c++ is
# Apple clang, which rejects that flag outright.  Build it with Homebrew
# LLVM clang instead — it supports -fopenmp and bundles libomp.  Linux
# uses gcc, which handles -fopenmp natively, so no override there.
ifeq ($(UNAME_S),Darwin)
BREW_LLVM      := $(shell brew --prefix llvm 2>/dev/null)
BREW_EIGEN     := $(shell brew --prefix eigen 2>/dev/null)
# Homebrew clang for -fopenmp/libomp, plus an explicit Eigen include
# path: nextpnr's CMake reads include_directories(${EIGEN3_INCLUDE_DIRS})
# (plural) but config-mode find_package(Eigen3) only sets the singular
# var, so the header dir is otherwise never added on macOS.
NEXTPNR_CMAKE  := -DCMAKE_C_COMPILER=$(BREW_LLVM)/bin/clang \
                  -DCMAKE_CXX_COMPILER=$(BREW_LLVM)/bin/clang++ \
                  -DEIGEN3_INCLUDE_DIRS=$(BREW_EIGEN)/include/eigen3
# openFPGALoader includes <libusb.h>, but Homebrew's header is at
# include/libusb-1.0/libusb.h.  It only wires up LIBUSB_INCLUDE_DIRS when a
# libusb cable is enabled, and even then CMake may not surface brew's keg path,
# so add brew's prefix (for pkg-config/find_package) + the explicit libusb -I.
# brew --prefix libusb is the version-independent opt symlink (…/opt/libusb),
# so the -I/-L follow the current version.  The -L matters because pkg-config
# can bake a *versioned* Cellar lib path (…/Cellar/libusb/1.0.NN/lib) into the
# link that dies the moment you `brew upgrade libusb`; the opt path never does.
BREW_LIBUSB    := $(shell brew --prefix libusb 2>/dev/null)
OFL_CMAKE      := -DCMAKE_PREFIX_PATH="$(shell brew --prefix 2>/dev/null)" \
                  -DCMAKE_CXX_FLAGS="-I$(BREW_LIBUSB)/include/libusb-1.0" \
                  -DCMAKE_EXE_LINKER_FLAGS="-L$(BREW_LIBUSB)/lib"
else ifeq ($(UNAME_S),Linux)
# Pin cmake's Python3 to the Boost-matched system interpreter so
# find_package picks a python with an installed libboost_python component.
NEXTPNR_CMAKE  := $(if $(SYS_PYTHON),-DPython3_EXECUTABLE=$(SYS_PYTHON))
endif

$(NEXTPNR_BIN): $(DEPS)/.initialised $(NEXTPNR_DIR)/xilinx/pack_dram.cc $(NEXTPNR_DIR)/xilinx/pack_clocking_xc7.cc $(NEXTPNR_DIR)/common/router2.cc
ifeq ($(UNAME_S),Darwin)
	@test -x "$(BREW_LLVM)/bin/clang++" || { \
	   echo "Homebrew LLVM clang not found — run 'make deps' (or 'brew install llvm')." >&2; \
	   exit 1; }
endif
	cmake -S $(NEXTPNR_DIR) -B $(NEXTPNR_DIR)/build \
	    -DARCH=xilinx \
	    -DCMAKE_BUILD_TYPE=Release \
	    $(NEXTPNR_CMAKE)
	cmake --build $(NEXTPNR_DIR)/build -j$$(getconf _NPROCESSORS_ONLN)


# ─── prjxray ───────────────────────────────────────────────────────────

$(FRAMES2BIT): $(DEPS)/.initialised
	cmake -S $(PRJXRAY_DIR) -B $(PRJXRAY_DIR)/build \
	    -DCMAKE_BUILD_TYPE=Release \
	    -DPRJXRAY_BUILD_TESTING=OFF
	cmake --build $(PRJXRAY_DIR)/build -j$$(getconf _NPROCESSORS_ONLN) \
	    --target xc7frames2bit

# Self-contained Python venv for prjxray's utils.  requirements.txt has
# relative editable installs (-e third_party/fasm, -e .), so pip must run
# from inside the prjxray tree.
$(PRJXRAY_STAMP): $(DEPS)/.initialised $(PRJXRAY_DIR)/requirements.txt
	$(PYTHON) -m venv $(PRJXRAY_VENV)
	$(PRJXRAY_VENV)/bin/pip install --upgrade pip wheel
	cd $(PRJXRAY_DIR) && env/bin/pip install -r requirements.txt
	@touch $@


# ─── openFPGALoader ────────────────────────────────────────────────────

$(OFL_BIN): $(DEPS)/.initialised
	cmake -S $(OPENFLD_DIR) -B $(OPENFLD_DIR)/build \
	    -DCMAKE_BUILD_TYPE=Release $(OFL_CMAKE)
	cmake --build $(OPENFLD_DIR)/build -j$$(getconf _NPROCESSORS_ONLN)


# ─── demo build (johnson) — stock yosys, no Vivado/SVS ─────────────────

$(DEMO_JSON): $(DEMO)/top.v $(DEMO)/counter25_core.v
	cd $(DEMO) && $(YOSYS) -p "read_verilog -sv top.v counter25_core.v; \
	    hierarchy -top top; synth_xilinx -flatten -family xc7; write_json $(DEMO_JSON)"

$(DEMO_FASM): $(DEMO_JSON) $(NEXTPNR_BIN) $(CHIPDB)
	cd $(DEMO) && \
	    NEXTPNR_ARC_MAX_VISIT=2000000 \
	    $(NEXTPNR_BIN) --router router1 \
	        --chipdb $(CHIPDB) --xdc top.xdc \
	        --json $(DEMO_JSON) --fasm $@ --freq 200

$(DEMO_FRAMES): $(DEMO_FASM) $(PRJXRAY_DB_OK) | $(PRJXRAY_STAMP)
	XRAY_ALLOW_MISSING_FEATURES=1 \
	$(PRJXRAY_PY) $(FASM2FRAMES) \
	    --db-root $(PRJXRAY_DB) --part $(PART) $< $@

$(DEMO_BIT): $(DEMO_FRAMES) $(FRAMES2BIT) $(PRJXRAY_DB_OK)
	$(FRAMES2BIT) \
	    --part_file $(PRJXRAY_DB)/$(PART)/part.yaml \
	    --part_name $(PART) \
	    --frm_file $< --output_file $@


# ─── telegraph build (same pipeline, separate sources) ─────────────────

$(TG_JSON): $(TG_DIR)/top.v $(TG_DIR)/telegraph_core.v
	cd $(TG_DIR) && $(YOSYS) -p "read_verilog -sv top.v telegraph_core.v; \
	    hierarchy -top top; synth_xilinx -flatten -family xc7; write_json $(TG_JSON)"

# router1 now sources GND/VCC from the nearest local pseudo-constant wire
# (the Vivado-style distributed-constant routing ported from router2).  The
# only sinks it can't reach are CARRY4.S padding inputs on the unused upper
# lanes of each counter's top CARRY4 — those are don't-care (their sum and
# carry-out feed nothing), so the visit budget + skip-failed-arcs leaves them
# unrouted harmlessly.
# Leading '-': nextpnr exits non-zero here because the don't-care CARRY4.S
# padding arcs are skipped (and timing misses 200 MHz, as the johnson demo
# also does).  The fasm is written before that exit, so ignore the status
# and let the pipeline continue.
$(TG_FASM): $(TG_JSON) $(NEXTPNR_BIN) $(CHIPDB)
	-cd $(TG_DIR) && \
	    NEXTPNR_ARC_MAX_VISIT=2000000 \
	    $(NEXTPNR_BIN) --router router1 \
	        --chipdb $(CHIPDB) --xdc top.xdc \
	        --json $(TG_JSON) --fasm $@ --freq 200

$(TG_FRAMES): $(TG_FASM) $(PRJXRAY_DB_OK) | $(PRJXRAY_STAMP)
	XRAY_ALLOW_MISSING_FEATURES=1 \
	$(PRJXRAY_PY) $(FASM2FRAMES) \
	    --db-root $(PRJXRAY_DB) --part $(PART) $< $@

$(TG_BIT): $(TG_FRAMES) $(FRAMES2BIT) $(PRJXRAY_DB_OK)
	$(FRAMES2BIT) \
	    --part_file $(PRJXRAY_DB)/$(PART)/part.yaml \
	    --part_name $(PART) \
	    --frm_file $< --output_file $@


# ─── calculator (uartram) — fully-open yosys flow (NO Vivado, NO plugin) ─
# The UART DSP calculator (soft CPU + DSP48E1 + block RAM), synthesised by
# STOCK yosys reading the SystemVerilog directly (read_verilog -sv), then the
# same open P&R / bitstream back-end as the demos.  100%-open front-to-back.
# Unlike uartram/build_open_min.sh (which synthesises via Vivado) this needs no
# Vivado; and unlike the earlier yosys-slang route it needs no plugin — just
# yosys (brew install yosys / apt install yosys / oss-cad-suite).  Builds on
# macOS too.
#
# xil_bb.v supplies black-box stubs for IBUF/OBUF/BUFG/IBUFDS/DSP48E1 with full
# Vivado params (yosys's built-in DSP48E1 lacks them); it is read first.
#
# Default clock = the 156.25 MHz Si570 USER_CLOCK (top_min_uc.xdc) for timing
# margin — the 200 MHz onboard SYSCLK is marginal in nextpnr.  For sysclk 200:
#   make calc CALC_DEFINE= CALC_XDC=top_min.xdc CALC_FREQ=200
CALC_DIR    := $(ROOT)/uartram
CALC_BIT    := $(CALC_DIR)/uartram_calc.bit
CALC_FRAMES := $(CALC_DIR)/uartram_calc.frames
CALC_FASM   := $(CALC_DIR)/uartram_calc.fasm
CALC_JSON   := $(CALC_DIR)/uartram_calc.json
CALC_SRCS   := top_min.sv calc_core.sv byte_fifo.sv lfsr_div.sv uart_rx_lfsr.sv \
               uart_src/uart_transmitter.sv uart_src/slib_input_sync.sv
CALC_DEPS   := $(addprefix $(CALC_DIR)/,$(CALC_SRCS) xil_bb.v calc_init.svh)
CALC_XDC    ?= top_min_uc.xdc
CALC_DEFINE ?= -DUSE_USERCLK
# nextpnr placement is not fully deterministic, so sweep seeds and take the
# first that meets CALC_FREQ (fall back to the best if none do).  At 156 MHz
# (userclk) every seed has margin; 200 MHz (sysclk) is tight (~1/7 seeds).
CALC_SEEDS  ?= 1 4 42 19 12 31 7 23 2 3
CALC_FREQ   ?= 156

YOSYS        ?= $(firstword $(wildcard $(HOME)/oss-cad-suite/bin/yosys \
                  $(HOME)/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys) yosys)

calc calc.bit: $(CALC_BIT)
	@echo "Calculator bit: $(CALC_BIT)  (flash: make calc-flash)"

# stock-yosys synthesis -> nextpnr JSON (no Vivado, no SVS, no plugin)
$(CALC_JSON): $(CALC_DEPS)
	cd $(CALC_DIR) && $(YOSYS) -p "read_verilog -sv $(CALC_DEFINE) xil_bb.v $(CALC_SRCS); \
	    hierarchy -top top; synth_xilinx -flatten -family xc7; write_json $(CALC_JSON)"

# nextpnr seed sweep (each run serialised via flock): take the first seed that
# meets CALC_FREQ; if none do, use the best-Fmax result and warn.
$(CALC_FASM): $(CALC_JSON) $(CALC_DIR)/$(CALC_XDC) $(NEXTPNR_BIN) $(CHIPDB)
	@cd $(CALC_DIR) && best=0; bestfasm=; rm -f $@; \
	for s in $(CALC_SEEDS); do \
	  flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 \
	    $(NEXTPNR_BIN) --router router2 --seed $$s --chipdb $(CHIPDB) --xdc $(CALC_XDC) \
	      --json $(CALC_JSON) --fasm $@.s$$s --freq $(CALC_FREQ) >$@.s$$s.log 2>&1; \
	  f=$$(grep -i "Max frequency for clock 'clk'" $@.s$$s.log | tail -1 | grep -oE "[0-9]+\.[0-9]+" | head -1); \
	  echo "  nextpnr seed $$s -> $${f:-FAIL} MHz"; \
	  if [ -s $@.s$$s ] && awk "BEGIN{exit !($${f:-0}>=$(CALC_FREQ))}"; then \
	    cp $@.s$$s $@; echo "  -> meets $(CALC_FREQ) MHz at seed $$s"; break; fi; \
	  if [ -s $@.s$$s ] && awk "BEGIN{exit !($${f:-0}>$$best)}"; then best=$${f:-0}; bestfasm=$@.s$$s; fi; \
	done; \
	if [ ! -f $@ ]; then \
	  [ -n "$$bestfasm" ] || { echo "ERROR: no seed produced a routed fasm"; exit 1; }; \
	  echo "  WARNING: no seed met $(CALC_FREQ) MHz; using best ($$best MHz). Retry with more CALC_SEEDS."; \
	  cp $$bestfasm $@; fi; \
	rm -f $@.s*

# fasm2frames + the rx-input IOB frame patch (AU33; see patch_rx_iob.py)
$(CALC_FRAMES): $(CALC_FASM) $(PRJXRAY_DB_OK) | $(PRJXRAY_STAMP)
	XRAY_ALLOW_MISSING_FEATURES=1 \
	$(PRJXRAY_PY) $(FASM2FRAMES) --db-root $(PRJXRAY_DB) --part $(PART) $< $@.tmp
	$(PRJXRAY_PY) $(CALC_DIR)/patch_rx_iob.py $@.tmp $@
	@rm -f $@.tmp

$(CALC_BIT): $(CALC_FRAMES) $(FRAMES2BIT) $(PRJXRAY_DB_OK)
	$(FRAMES2BIT) \
	    --part_file $(PRJXRAY_DB)/$(PART)/part.yaml \
	    --part_name $(PART) \
	    --frm_file $< --output_file $@

calc-flash: $(CALC_BIT) | $(OFL_BIN)
	$(OFL_BIN) --cable digilent --freq 15000000 $(CALC_BIT)


# ─── picosoc (open-flow soft SoC: picorv32 + UART + BRAM, NO Vivado) ─────
# Driven by picosoc/build_open.sh (riscv-gcc firmware -> yosys -> nextpnr ->
# prjxray -> bit).  Needs a RISC-V bare-metal gcc for the firmware:
#   macOS:  brew install riscv-gnu-toolchain   (or riscv64-elf-gcc)
#   Linux:  apt install gcc-riscv64-unknown-elf (or your distro's rv32 gcc)
# Output: /tmp/picosoc_open.bit .  Override SEED / FREQ / RISCV_PREFIX as needed.
PICOSOC_BIT := /tmp/picosoc_open.bit

picosoc: $(NEXTPNR_BIN) $(CHIPDB) $(FRAMES2BIT) $(PRJXRAY_DB_OK) | $(PRJXRAY_STAMP)
	@command -v $${RISCV_PREFIX:-riscv64-unknown-elf}-gcc >/dev/null 2>&1 || command -v riscv64-elf-gcc >/dev/null 2>&1 || { \
	   echo "No RISC-V gcc found -- install one (see the picosoc comment in the Makefile)." >&2; exit 1; }
	cd picosoc && YOSYS='$(YOSYS)' bash build_open.sh
	@echo "PicoSoC bit: $(PICOSOC_BIT)  (flash: make picosoc-flash)"

picosoc-flash: | $(OFL_BIN)
	$(OFL_BIN) --cable digilent --freq 15000000 $(PICOSOC_BIT)


# ─── clean ─────────────────────────────────────────────────────────────

clean:
	rm -f $(DEMO_BIT) $(DEMO_FRAMES) $(DEMO_FASM) $(DEMO_JSON) \
	    $(DEMO)/top.edif \
	    $(TG_BIT) $(TG_FRAMES) $(TG_FASM) $(TG_JSON) $(TG_DIR)/top.edif \
	    $(CALC_BIT) $(CALC_FRAMES) $(CALC_FASM) $(CALC_JSON)
	rm -rf $(NEXTPNR_DIR)/build $(PRJXRAY_DIR)/build \
	    $(OPENFLD_DIR)/build $(PRJXRAY_VENV)

distclean: clean
	rm -f $(CHIPDB) $(DEPS)/.initialised
	git submodule deinit -f --all 2>/dev/null || true

# ─── svs_arp: fully-open eth-arp (SGMII ARP responder) ────────────────────
# Vivado post-synth netlist (checked in) -> yosys json -> SVS topographical
# placer (separate repo, OCaml/dune) -> carry-slice stamper -> nextpnr-xilinx
# router2 -> prjxray fasm2frames/xc7frames2bit.  No Vivado anywhere.
# VALIDATED ON VC707 SILICON 2026-07-13 (arping 9/9, 0.21ms RTT).
#
# Needs the SVS placer repo (override SVS=/path):  opam switch 5.3.0 + dune.
#   macOS:  brew install opam && opam init && opam switch create 5.3.0 \
#           && opam install dune yojson
# NOTE: the SA placement is deterministic for a given yosys json, but a
# different yosys version can reorder cells and shift the placement; the
# result should still route + gate, just not bit-identically.
# System-Verilog-suite is vendored as a submodule (deps/System-Verilog-suite).
# Override SVS=/path to use an external checkout instead.
SVS ?= $(CURDIR)/deps/System-Verilog-suite
SVS_PLACER := $(SVS)/_build/default/place_lef.exe

# Build the SVS OCaml tools from the submodule (needs opam switch 5.3.0 + dune).
# `make svs-tools` once after a fresh clone / submodule update.
svs-tools: | $(SVS)/dune-project
	@[ -f $(SVS)/dune-project ] || { echo "SVS submodule empty -- run: git submodule update --init deps/System-Verilog-suite" >&2; exit 1; }
	cd $(SVS) && dune build ./_build/default/sv_suite.exe ./_build/default/place_lef.exe
	@echo "SVS tools built: $(SVS_PLACER)"

# ---------------------------------------------------------------------------
# Build tree.  ALL SVS bit/fasm/frames + intermediates live under $(BUILD)
# (gitignored), one subdir per target -- never /tmp.  Layout:
#   build/svs_arp/          pinned silicon-validated open flow
#   build/svs_arp_synth/    eth-arp from SVS synthesis (open backend)
#   build/hybrid_<layer>/   golden shell + one SVS layer (Vivado)
#   build/diag/             PCS status-observer bitstreams
# each holds  <name>.bit  <name>.fasm  <name>.frames  + arp.json/.edf/logs.
BUILD ?= $(CURDIR)/build
SVS_ARP_WORK  := $(BUILD)/svs_arp
SVS_ARP_BIT   := $(SVS_ARP_WORK)/svs_arp.bit
# The eth-arp GT/SGMII config needs the AUTHORITATIVE prjxray DB (local
# ground-truth fixes: GT frame addressing, ppip de-shadowing, CLBLM MC31),
# not the pristine deps/prjxray fetch.  Override if yours lives elsewhere.
PRJXRAY_AUTH ?= $(shell [ -d $(HOME)/prjxray/database/virtex7 ] && echo $(HOME)/prjxray || echo $(PRJXRAY_DIR))

$(SVS_PLACER):
	@[ -d $(SVS) ] || { echo "SVS placer repo not found at $(SVS) -- set SVS=/path/to/System-Verilog-suite" >&2; exit 1; }
	cd $(SVS) && eval $$(opam env --switch=5.3.0 2>/dev/null || opam env) && dune build place_lef.exe

# Re-sync submodules whenever the parent's pinned commits moved (a plain
# `git pull` does NOT update submodules; the .initialised stamp runs once).
.PHONY: submodules-sync
submodules-sync: | $(DEPS)/.initialised
	@git submodule sync --quiet
	@if git submodule status | grep -q '^+'; then \
	   echo "== submodules out of sync with pinned commits -- updating =="; \
	   git submodule update --init --recursive; \
	 fi

svs_arp: submodules-sync $(NEXTPNR_BIN) $(CHIPDB) $(FRAMES2BIT) $(PRJXRAY_DB_OK) | svs-tools $(PRJXRAY_STAMP)
	@mkdir -p $(SVS_ARP_WORK)
	SVS='$(SVS)' YOSYS='$(YOSYS)' PRJXRAY='$(PRJXRAY_AUTH)' NEXTPNR='$(NEXTPNR_BIN)' \
	  WORK='$(SVS_ARP_WORK)' OUT='$(SVS_ARP_BIT)' bash ethsoc/build_svs_arp.sh
	@echo "eth-arp open bit: $(SVS_ARP_BIT)  (flash: make svs_arp-flash; then arping 192.168.1.100)"

svs_arp-flash: | $(OFL_BIN)
	$(OFL_BIN) --cable digilent --freq 15000000 $(SVS_ARP_BIT)

# ---------------------------------------------------------------------------
# eth-arp from SVS SYNTHESIS through the fully-open backend, plus OpenTimer.
#   svs_arp_synth      RTL source -> SVS synth (arp_open.lua: gate_map
#                      wrappers + primitive-PCS passthrough, the 15-bug-
#                      campaign-validated frontend) -> SVS topographical
#                      placer -> carry_stamp -> nextpnr router2 -> fasm ->
#                      prjxray frames -> bitstream.  Also writes the ROUTED
#                      json (per-net ROUTING attrs) for the STA step.
#   svs_arp_synth-sta  OpenTimer two-corner STA of that routed design
#                      (json2ot Liberty from prjxray SDF calibration,
#                      route2spef per-net Elmore wires, auto-SDC clock
#                      seeding).  OT_PERIOD_NS defaults to 8.0 = the
#                      125 MHz eth domain; the 50 MHz cpu domain is then
#                      over-constrained 2.5x -- read per-clock slacks in
#                      the report, not just the single WNS.
#   svs_arp_synth-timing  chain both.
# NOTE unlike `svs_arp` (pinned silicon-validated Vivado-netlist json),
# the synth flow re-places and re-routes fresh: SKIPS=0 is gated in the
# script but a zero-skip route is NOT automatically functional -- validate
# on hardware (make svs_arp_synth-flash; arping 192.168.1.100).
#
# KNOWN BLOCKER (2026-07-18): synth->place SUCCEEDS; nextpnr-xilinx's
# timing analysis then aborts on "combinatorial loops" whose SCC contains
# ONLY the PCS rx_elastic_buffer RAM64M read outputs (DPR O6) feeding their
# rd_data FFs -- a DAG, so a false positive from nextpnr mis-modelling the
# async-read RAM64M packed into a SLICEM shared W/R LUT.  The pinned
# `svs_arp` netlist (Vivado RAM64M w/ RTL_RAM_* attrs) packs cleanly; the
# SVS-emitted one lacks whatever nextpnr keys on.  Under investigation;
# until resolved, svs_arp_synth-sta runs against a routable design via
# STA_JSON/STA_FASM (below).
SVS_ARP_SYNTH_WORK := $(BUILD)/svs_arp_synth
SVS_ARP_SYNTH_BIT  := $(SVS_ARP_SYNTH_WORK)/svs_arp_synth.bit
OT_PERIOD_NS ?= 8.0
SVS_SUITE_EXE := $(SVS)/_build/default/sv_suite.exe

svs_arp_synth: submodules-sync $(NEXTPNR_BIN) $(CHIPDB) $(FRAMES2BIT) $(PRJXRAY_DB_OK) | svs-tools $(PRJXRAY_STAMP)
	@[ -x $(SVS_SUITE_EXE) ] || { echo "sv_suite.exe not built at $(SVS_SUITE_EXE) -- dune build in $(SVS)" >&2; exit 1; }
	@mkdir -p $(SVS_ARP_SYNTH_WORK)
	SVS_SYNTH=1 SVS='$(SVS)' YOSYS='$(YOSYS)' PRJXRAY='$(PRJXRAY_AUTH)' NEXTPNR='$(NEXTPNR_BIN)' \
	  WORK='$(SVS_ARP_SYNTH_WORK)' OUT='$(SVS_ARP_SYNTH_BIT)' bash ethsoc/build_svs_arp.sh
	@echo "SVS-synth open bit: $(SVS_ARP_SYNTH_BIT)  routed json: $(SVS_ARP_SYNTH_WORK)/arp_routed.json"

# OpenTimer two-corner STA.  STA_JSON / STA_FASM select the design: default is
# the SVS-synth routed output; if the synth route was blocked (see KNOWN
# BLOCKER note above svs_arp_synth) point them at any placed+routed pair, e.g.
#   make svs_arp_synth-sta STA_JSON=build/svs_arp/arp_stamped.json \
#                          STA_FASM=build/svs_arp/arp.fasm
# route2spef uses per-net Elmore from the routed json's ROUTING attrs, else a
# flat FASM-census wire model (first-order; over-penalises long carry chains).
STA_JSON ?= $(SVS_ARP_SYNTH_WORK)/arp_routed.json
STA_FASM ?= $(SVS_ARP_SYNTH_WORK)/arp.fasm
# (fall back to the pinned build's artifacts if the synth route was blocked:
#  make svs_arp_synth-sta STA_JSON=$(SVS_ARP_WORK)/arp_stamped.json STA_FASM=$(SVS_ARP_WORK)/arp.fasm)
svs_arp_synth-sta:
	@[ -s $(STA_JSON) ] || { echo "no STA json ($(STA_JSON)) -- run 'make svs_arp_synth' or set STA_JSON=/path" >&2; exit 1; }
	@[ -s $(STA_FASM) ] || { echo "no STA fasm ($(STA_FASM)) -- set STA_FASM=/path" >&2; exit 1; }
	OT_NPATHS=10 bash ethsoc/openflow/opentimer/run_ot_json.sh \
	  $(STA_JSON) $(STA_FASM) $(OT_PERIOD_NS) svsarp
	@echo "--- OpenTimer report: ethsoc/openflow/opentimer/svsarp.ot.rpt ---"
	@grep -aE "WNS|slack|VIOLATED|MET" ethsoc/openflow/opentimer/svsarp.ot.rpt | head -8

svs_arp_synth-timing: svs_arp_synth svs_arp_synth-sta

svs_arp_synth-flash: | $(OFL_BIN)
	$(OFL_BIN) --cable digilent --freq 15000000 $(SVS_ARP_SYNTH_BIT)

# ---------------------------------------------------------------------------
# Silicon-bisection HYBRIDS: golden Vivado shell + ONE SVS-synthesized layer
# linked as an EDIF black-box.  Each isolates a slice of the eth stack; all
# five reached 15/15 ARP on VC707 during the 2026-07 SVS bug campaign.
#   svs_hybrid_ethmacro   SVS eth_macro   in golden top+framing+arp
#   svs_hybrid_sgmii      SVS sgmii_soc   in golden everything
#   svs_hybrid_framing    SVS framing_top in golden top+arp
#   svs_hybrid_arp        SVS arp_ctrl    in golden eth stack
# Needs a full Vivado (VIVADO=/path; default /opt/Xilinx/Vivado/2020.1).
# Bit lands in build/hybrid_<layer>/; flash with
# svs_hybrid_<layer>-flash.
VIVADO ?= /opt/Xilinx/Vivado/2020.1/bin/vivado
ETHSOC ?= $(CURDIR)/ethsoc
define SVS_HYBRID_RULE
svs_hybrid_$(1): | svs-tools
	@mkdir -p $(BUILD)/hybrid_$(1)
	SVS='$(SVS)' VIVADO='$(VIVADO)' W='$(BUILD)/hybrid_$(1)' \
	  bash ethsoc/svs_race/build_hybrid.sh $(1)
svs_hybrid_$(1)-flash: | $(OFL_BIN)
	$(OFL_BIN) --cable digilent --freq 15000000 $$(ls $(BUILD)/hybrid_$(1)/*.bit | head -1)
endef
$(foreach L,ethmacro sgmii framing arp,$(eval $(call SVS_HYBRID_RULE,$(L))))
svs_hybrids: svs_hybrid_ethmacro svs_hybrid_sgmii svs_hybrid_framing svs_hybrid_arp

# PCS status-observer diagnostic (sgmii_soc alone, TX idle; DIP-paged status/
# sticky/heartbeat LEDs -- vc707_sgmii_diag.v).  diag_gold.bit = all-Vivado
# baseline; diag_svs.bit links the SVS sgmii_soc EDIF (needs svs_hybrid_sgmii
# first, or SGMII_EDIF=/path).  Both land in build/diag/.
svs_diag:
	@mkdir -p $(BUILD)/diag
	W='$(BUILD)/diag' ETH='$(ETHSOC)' $(VIVADO) -mode batch \
	  -source ethsoc/svs_race/diag.tcl -journal $(BUILD)/diag/d.jou -log $(BUILD)/diag/d.log \
	  || { echo "(diag_svs half needs svs_hybrid_sgmii or SGMII_EDIF=)"; }
	@ls -l $(BUILD)/diag/*.bit 2>/dev/null
