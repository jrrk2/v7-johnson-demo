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
    cmake pkg-config git curl \
    boost eigen python@3.12 \
    libftdi libusb hidapi \
    opam \
    icarus-verilog \
    zstd

# Project X-Ray Python venv.
if [ ! -d deps/prjxray/env ] && [ -d deps/prjxray ]; then
    pushd deps/prjxray >/dev/null
    python3 -m venv env
    env/bin/pip install --upgrade pip
    env/bin/pip install -r requirements.txt 2>/dev/null || \
      env/bin/pip install simplejson pyyaml fasm intervaltree numpy progressbar2
    popd >/dev/null
fi

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
