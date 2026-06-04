#!/bin/bash
# Install build dependencies for v7-johnson-demo on Ubuntu/Debian.
# Requires sudo.  Idempotent — safe to re-run.
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config git curl ca-certificates zstd \
    python3 python3-pip python3-venv \
    libboost-all-dev libeigen3-dev \
    libftdi-dev libusb-1.0-0-dev libudev-dev libhidapi-dev \
    libgtk-3-dev libjpeg-dev \
    opam ocaml-base-compiler \
    iverilog

# Project X-Ray's Python venv (deps/prjxray/env) is built by the
# Makefile from prjxray's requirements.txt — see the $(PRJXRAY_PY)
# target — so it stays in the build graph and isolated from any
# system-wide prjxray install.

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
