#!/bin/bash
# Install build dependencies for v7-johnson-demo on macOS.
# Uses homebrew (https://brew.sh).  Idempotent — safe to re-run.
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found.  Install from https://brew.sh first." >&2
    exit 1
fi

brew update
brew install \
    cmake pkg-config git curl zstd \
    boost eigen python@3.12 \
    libftdi libusb hidapi \
    llvm libomp \
    yosys \
    icarus-verilog

# Project X-Ray's Python venv (deps/prjxray/env) is built by the
# Makefile from prjxray's requirements.txt — see the $(PRJXRAY_PY)
# target — so it stays in the build graph and isolated from any
# system-wide prjxray install.
#
# Synthesis is stock yosys (read_verilog -sv + synth_xilinx) — no OCaml/opam,
# no yosys plugin.  brew's yosys works; for a newer one install oss-cad-suite
# and point YOSYS at it.

echo "macOS deps installed."
