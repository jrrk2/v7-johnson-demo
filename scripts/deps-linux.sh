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
    yosys \
    iverilog

# Project X-Ray's Python venv (deps/prjxray/env) is built by the
# Makefile from prjxray's requirements.txt — see the $(PRJXRAY_PY)
# target — so it stays in the build graph and isolated from any
# system-wide prjxray install.
#
# Synthesis is stock yosys (read_verilog -sv + synth_xilinx) — no OCaml/opam,
# no yosys plugin.  apt's yosys works; for a newer one install oss-cad-suite
# and point YOSYS at it.

echo "Linux deps installed."
