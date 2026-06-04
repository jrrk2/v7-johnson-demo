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
    opam \
    icarus-verilog

# Project X-Ray's Python venv (deps/prjxray/env) is built by the
# Makefile from prjxray's requirements.txt — see the $(PRJXRAY_PY)
# target — so it stays in the build graph and isolated from any
# system-wide prjxray install.

# OCaml side for System-Verilog-suite.
if ! opam switch list 2>/dev/null | grep -q '5\.3\.0'; then
    opam init -y --bare 2>/dev/null || true
    opam switch create 5.3.0 --packages=ocaml-base-compiler.5.3.0 -y
fi
eval "$(opam env --switch=5.3.0 --set-switch)"
opam install -y dune menhir hardcaml hardcaml-circuits hardcaml-c \
    hardcaml-step-testbench base stdio core cmdliner zarith \
    z3 yojson lua-cli 2>/dev/null || true

echo "macOS deps installed."
