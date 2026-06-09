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
SVS_DIR        := $(DEPS)/System-Verilog-suite

# Chipdb fetched from openXC7 release rather than built from scratch
# (full build needs RapidWright, ~10 min).  Update CHIPDB_TAG to a
# newer release tag when one is published.
# The release publishes the chipdb zstd-compressed (xc7vx485t.bin.zst);
# we fetch that and decompress to the plain .bin nextpnr expects.
CHIPDB_TAG     := chipdb-2026-06-03
CHIPDB_URL     := https://github.com/openXC7/nextpnr-xilinx/releases/download/$(CHIPDB_TAG)/xc7vx485t.bin.zst
CHIPDB         := $(NEXTPNR_DIR)/xilinx/xc7vx485t.bin

# Project X-Ray database (segbits / tilegrid / part.yaml etc) is a
# fuzzer artefact, also published as a release tarball — pulling it
# avoids needing Vivado to re-fuzz from scratch (~hours of build).
PRJXRAY_DB_TAG := db-virtex7-2026-06-06
PRJXRAY_DB_URL := https://github.com/openXC7/prjxray/releases/download/$(PRJXRAY_DB_TAG)/prjxray-database-virtex7-2026-06-06.tar.zst
PRJXRAY_DB_TAR := $(BUILD)/$(PRJXRAY_DB_TAG).tar.zst
# Sentinel file that proves the DB tarball has been extracted.
PRJXRAY_DB_OK  := $(PRJXRAY_DIR)/database/virtex7/xc7vx485tffg1761-2/part.yaml

# Cargo of tool binaries the demo step consumes.
NEXTPNR_BIN    := $(NEXTPNR_DIR)/build/nextpnr-xilinx
SVS_BIN        := $(SVS_DIR)/_build/default/sv_suite.exe
OFL_BIN        := $(OPENFLD_DIR)/build/openFPGALoader
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
DEMO_RECIPE    := $(DEMO)/recipe.lua

# Second example: the telegraph (repeating bit-banged UART).  Same flow,
# its own source directory + artefacts.
TG_DIR         := $(ROOT)/telegraph
TG_BIT         := $(TG_DIR)/telegraph.bit
TG_FASM        := $(TG_DIR)/telegraph.fasm
TG_FRAMES      := $(TG_DIR)/telegraph.frames
TG_JSON        := $(TG_DIR)/top.json
TG_RECIPE      := $(TG_DIR)/recipe.lua


# ─── high-level targets ────────────────────────────────────────────────

.PHONY: all deps tools chipdb johnson.bit telegraph telegraph.bit flash telegraph-flash clean distclean help

# Keep intermediates even if a recipe exits non-zero (the telegraph route
# step does, on its skipped don't-care CARRY4.S arcs + timing miss).
.PRECIOUS: $(TG_FASM) $(TG_FRAMES) $(DEMO_FASM) $(DEMO_FRAMES)

all: $(DEMO_BIT)
	@echo
	@echo "=== Build complete ==="
	@echo "Bit: $(DEMO_BIT)"
	@echo "Flash with: make flash"

help:
	@sed -n 's/^# //p; /^\.PHONY/q' $(firstword $(MAKEFILE_LIST))

tools: $(NEXTPNR_BIN) $(SVS_BIN) $(OFL_BIN) $(FRAMES2BIT) $(CHIPDB) $(PRJXRAY_DB_OK)
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
else ifeq ($(UNAME_S),Linux)
# Pin cmake's Python3 to the Boost-matched system interpreter so
# find_package picks a python with an installed libboost_python component.
NEXTPNR_CMAKE  := $(if $(SYS_PYTHON),-DPython3_EXECUTABLE=$(SYS_PYTHON))
endif

$(NEXTPNR_BIN): $(DEPS)/.initialised
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
	    -DCMAKE_BUILD_TYPE=Release
	cmake --build $(OPENFLD_DIR)/build -j$$(getconf _NPROCESSORS_ONLN)


# ─── System-Verilog-suite (OCaml + dune + hardcaml) ────────────────────

$(SVS_BIN): $(DEPS)/.initialised
	cd $(SVS_DIR) && dune build sv_suite.exe


# ─── demo build ────────────────────────────────────────────────────────

$(DEMO_JSON): $(SVS_BIN) $(DEMO_RECIPE) | $(SVS_DIR)
	cd $(DEMO) && $(SVS_BIN) script $(DEMO_RECIPE) $(SVS_DIR)

$(DEMO_FASM): $(DEMO_JSON) $(NEXTPNR_BIN) $(CHIPDB)
	cd $(DEMO) && \
	    NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_SKIP_FAILED_ARCS=1 \
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

$(TG_JSON): $(SVS_BIN) $(TG_RECIPE) $(TG_DIR)/telegraph_core.v $(TG_DIR)/top.v | $(SVS_DIR)
	cd $(TG_DIR) && $(SVS_BIN) script $(TG_RECIPE) $(SVS_DIR)

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
	    NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_SKIP_FAILED_ARCS=1 \
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


# ─── clean ─────────────────────────────────────────────────────────────

clean:
	rm -f $(DEMO_BIT) $(DEMO_FRAMES) $(DEMO_FASM) $(DEMO_JSON) \
	    $(DEMO)/top.edif \
	    $(TG_BIT) $(TG_FRAMES) $(TG_FASM) $(TG_JSON) $(TG_DIR)/top.edif
	rm -rf $(NEXTPNR_DIR)/build $(PRJXRAY_DIR)/build \
	    $(OPENFLD_DIR)/build $(SVS_DIR)/_build $(PRJXRAY_VENV)

distclean: clean
	rm -f $(CHIPDB) $(DEPS)/.initialised
	git submodule deinit -f --all 2>/dev/null || true
