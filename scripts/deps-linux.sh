#!/bin/bash
# Install build dependencies for v7-johnson-demo on Ubuntu/Debian.
# Requires sudo.  Idempotent — safe to re-run.
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config git curl ca-certificates \
    python3 python3-pip python3-venv \
    libboost-all-dev libeigen3-dev \
    libftdi-dev libusb-1.0-0-dev libudev-dev libhidapi-dev \
    libgtk-3-dev libjpeg-dev \
    opam ocaml-base-compiler \
    iverilog \
    zstd

# Project X-Ray uses a Python venv with simplejson, pyyaml etc.
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
    opam init -y --bare --disable-sandboxing 2>/dev/null || true
    opam switch create 5.3.0 --packages=ocaml-base-compiler.5.3.0 -y
fi
eval "$(opam env --switch=5.3.0 --set-switch)"
opam install -y dune menhir hardcaml hardcaml-circuits hardcaml-c \
    hardcaml-step-testbench base stdio core cmdliner zarith \
    z3 yojson lua-cli 2>/dev/null || true

echo "Linux deps installed."
