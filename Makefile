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

# Where each tool lives after `git submodule update --init`.
NEXTPNR_DIR    := $(DEPS)/nextpnr-xilinx
PRJXRAY_DIR    := $(DEPS)/prjxray
OPENFLD_DIR    := $(DEPS)/openFPGALoader
SVS_DIR        := $(DEPS)/System-Verilog-suite

# Chipdb fetched from openXC7 release rather than built from scratch
# (full build needs RapidWright, ~10 min).  Update CHIPDB_TAG to a
# newer release tag when one is published.
CHIPDB_TAG     := chipdb-2026-06-03
CHIPDB_URL     := https://github.com/openXC7/nextpnr-xilinx/releases/download/$(CHIPDB_TAG)/xc7vx485t.bin
CHIPDB         := $(NEXTPNR_DIR)/xilinx/xc7vx485t.bin

# Cargo of tool binaries the demo step consumes.
NEXTPNR_BIN    := $(NEXTPNR_DIR)/build/nextpnr-xilinx
SVS_BIN        := $(SVS_DIR)/_build/default/sv_suite.exe
OFL_BIN        := $(OPENFLD_DIR)/build/openFPGALoader
FASM2FRAMES    := $(PRJXRAY_DIR)/utils/fasm2frames.py
FRAMES2BIT     := $(PRJXRAY_DIR)/build/tools/xc7frames2bit
PRJXRAY_DB     := $(PRJXRAY_DIR)/database/virtex7

# Demo design + intermediate artefacts.
PART           := xc7vx485tffg1761-2
DEMO_BIT       := $(DEMO)/counter28.bit
DEMO_FASM      := $(DEMO)/counter28.fasm
DEMO_FRAMES    := $(DEMO)/counter28.frames
DEMO_JSON      := $(DEMO)/top.json
DEMO_RECIPE    := $(DEMO)/recipe.lua


# ─── high-level targets ────────────────────────────────────────────────

.PHONY: all deps tools chipdb johnson.bit flash clean distclean help

all: $(DEMO_BIT)
	@echo
	@echo "=== Build complete ==="
	@echo "Bit: $(DEMO_BIT)"
	@echo "Flash with: make flash"

help:
	@sed -n 's/^# //p; /^\.PHONY/q' $(firstword $(MAKEFILE_LIST))

tools: $(NEXTPNR_BIN) $(SVS_BIN) $(OFL_BIN) $(FRAMES2BIT) $(CHIPDB)
	@echo "All tools built and chipdb fetched."

johnson.bit: $(DEMO_BIT)

flash: $(DEMO_BIT) | $(OFL_BIN)
	$(OFL_BIN) --cable digilent --freq 15000000 $(DEMO_BIT)


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
	   curl -fL -o $@ $(CHIPDB_URL); \
	fi


# ─── nextpnr-xilinx ────────────────────────────────────────────────────

$(NEXTPNR_BIN): $(DEPS)/.initialised
	cmake -S $(NEXTPNR_DIR) -B $(NEXTPNR_DIR)/build \
	    -DARCH=xilinx \
	    -DCMAKE_BUILD_TYPE=Release
	cmake --build $(NEXTPNR_DIR)/build -j$$(getconf _NPROCESSORS_ONLN)


# ─── prjxray ───────────────────────────────────────────────────────────

$(FRAMES2BIT): $(DEPS)/.initialised
	cmake -S $(PRJXRAY_DIR) -B $(PRJXRAY_DIR)/build \
	    -DCMAKE_BUILD_TYPE=Release \
	    -DPRJXRAY_BUILD_TESTING=OFF
	cmake --build $(PRJXRAY_DIR)/build -j$$(getconf _NPROCESSORS_ONLN) \
	    --target xc7frames2bit


# ─── openFPGALoader ────────────────────────────────────────────────────

$(OFL_BIN): $(DEPS)/.initialised
	cmake -S $(OPENFLD_DIR) -B $(OPENFLD_DIR)/build \
	    -DCMAKE_BUILD_TYPE=Release
	cmake --build $(OPENFLD_DIR)/build -j$$(getconf _NPROCESSORS_ONLN)


# ─── System-Verilog-suite (OCaml + dune + hardcaml) ────────────────────

$(SVS_BIN): $(DEPS)/.initialised
	cd $(SVS_DIR) && dune build sv_suite.exe


# ─── demo build ────────────────────────────────────────────────────────

$(DEMO_JSON): $(SVS_BIN) $(DEMO_RECIPE) | $(SVS_DIR)
	cd $(DEMO) && $(SVS_BIN) script $(DEMO_RECIPE)

$(DEMO_FASM): $(DEMO_JSON) $(NEXTPNR_BIN) $(CHIPDB)
	cd $(DEMO) && \
	    NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_SKIP_FAILED_ARCS=1 \
	    $(NEXTPNR_BIN) --router router1 \
	        --chipdb $(CHIPDB) --xdc top.xdc \
	        --json $(DEMO_JSON) --fasm $@ --freq 200

$(DEMO_FRAMES): $(DEMO_FASM) $(PRJXRAY_DB)
	@. $(PRJXRAY_DIR)/env/bin/activate 2>/dev/null || true; \
	XRAY_ALLOW_MISSING_FEATURES=1 \
	PATH=$(PRJXRAY_DIR)/env/bin:$$PATH \
	python3 $(FASM2FRAMES) \
	    --db-root $(PRJXRAY_DB) --part $(PART) $< $@

$(DEMO_BIT): $(DEMO_FRAMES) $(FRAMES2BIT)
	$(FRAMES2BIT) \
	    --part_file $(PRJXRAY_DB)/$(PART)/part.yaml \
	    --part_name $(PART) \
	    --frm_file $< --output_file $@


# ─── clean ─────────────────────────────────────────────────────────────

clean:
	rm -f $(DEMO_BIT) $(DEMO_FRAMES) $(DEMO_FASM) $(DEMO_JSON) \
	    $(DEMO)/top.edif
	rm -rf $(NEXTPNR_DIR)/build $(PRJXRAY_DIR)/build \
	    $(OPENFLD_DIR)/build $(SVS_DIR)/_build

distclean: clean
	rm -f $(CHIPDB) $(DEPS)/.initialised
	git submodule deinit -f --all 2>/dev/null || true
