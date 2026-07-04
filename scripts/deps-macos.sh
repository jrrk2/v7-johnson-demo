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

# The picosoc demo (`make picosoc`) also needs a RISC-V bare-metal gcc for its
# firmware.  The brew formula / tap varies and can be a long source build, so
# it is not installed here automatically -- any of riscv64-unknown-elf /
# riscv64-elf / riscv-none-elf gcc works (build_open.sh auto-detects; override
# RISCV_PREFIX otherwise).  A common choice:
#   brew tap riscv-software-src/riscv && brew install riscv-gnu-toolchain
if ! command -v riscv64-unknown-elf-gcc >/dev/null 2>&1 && \
   ! command -v riscv64-elf-gcc >/dev/null 2>&1 && \
   ! command -v riscv-none-elf-gcc >/dev/null 2>&1; then
    echo "NOTE: 'make picosoc' needs a RISC-V bare-metal gcc -- none found."
    echo "      e.g.  brew tap riscv-software-src/riscv && brew install riscv-gnu-toolchain"
fi

echo "macOS deps installed."
