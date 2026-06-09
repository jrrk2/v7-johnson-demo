#!/bin/bash
# Fast BRAM-INIT update on the bitstream flow.  Patches the calc program
# (calc_init.svh) into an already-placed-and-routed fasm and rebuilds the
# bitstream WITHOUT re-running Vivado synth / SVS / nextpnr.  ~seconds vs minutes.
# Placement & routing are unchanged; only the RAMB18 INIT_* contents change.
# usage: init_update.sh [calc_init.svh] [base.fasm] [out.bit]
set -e
ROOT=/home/jonathan/v7-johnson-demo
PXPY=$ROOT/deps/prjxray/env/bin/python
F2F=$ROOT/deps/prjxray/utils/fasm2frames.py
F2B=$ROOT/deps/prjxray/build/tools/xc7frames2bit
PXDB=$ROOT/deps/prjxray/database/virtex7
PART=xc7vx485tffg1761-2
SVH=${1:-$ROOT/uartram/calc_init.svh}
BASE=${2:-/tmp/uartram_uc_open.fasm}
OUT=${3:-/tmp/uartram_uc_open.bit}
PFASM=/tmp/uartram_init.fasm
echo "== patch BRAM INIT from $SVH into $BASE =="
$PXPY /tmp/bram_init.py "$SVH" "$BASE" "$PFASM"
echo "== fasm2frames =="
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $F2F --db-root $PXDB --part $PART "$PFASM" /tmp/uartram_init.frames >/tmp/init_f2f.out 2>&1 && echo "frames OK" || { echo F2F_FAIL; tail -3 /tmp/init_f2f.out; exit 1; }
echo "== patch rx IOB (prjxray AU33 LVCMOS18 input segbit gap) =="
$PXPY $ROOT/uartram/patch_rx_iob.py /tmp/uartram_init.frames /tmp/uartram_init_rx.frames && mv /tmp/uartram_init_rx.frames /tmp/uartram_init.frames
echo "== frames2bit =="
$F2B --part_file $PXDB/$PART/part.yaml --part_name $PART --frm_file /tmp/uartram_init.frames --output_file "$OUT" >/tmp/init_f2b.out 2>&1 && echo "bit OK -> $OUT" || { echo F2B_FAIL; exit 1; }
echo "INIT_UPDATE_DONE"
