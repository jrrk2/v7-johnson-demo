#!/bin/bash
# Open-flow build of the FULL calculator with the carry-free LFSR UART (top_min.sv):
# Vivado synth -> EDIF -> SVS json -> nextpnr (router2) -> fasm -> rx-IOB patch -> bit.
# Includes the prjxray rx-input segbit fix (patch_rx_iob.py, rx=AU33).
set -u
ROOT=/home/jonathan/v7-johnson-demo
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
SVS=$ROOT/deps/System-Verilog-suite/_build/default/sv_suite.exe
SVSDIR=$ROOT/deps/System-Verilog-suite
PXPY=$ROOT/deps/prjxray/env/bin/python
F2F=$ROOT/deps/prjxray/utils/fasm2frames.py
F2B=$ROOT/deps/prjxray/build/tools/xc7frames2bit
PXDB=$ROOT/deps/prjxray/database/virtex7
PART=xc7vx485tffg1761-2
SEEDS="${1:-4 7 12 19 23}"
cd $ROOT/uartram
say(){ echo "===== $* ====="; }
say "1/5 synth top_min (USE_USERCLK 156.25MHz)"
/opt/Xilinx/Vivado/2020.1/bin/vivado -mode batch -source vivado_edif_min_uc.tcl -nojournal -log /tmp/min_edif.log >/tmp/min_edif.out 2>&1
grep -E "INSTS:|MIN_EDIF_DONE|ERROR:" /tmp/min_edif.out | grep -v puts || { echo EDIF_FAIL; tail -8 /tmp/min_edif.out; exit 1; }
say "2/5 SVS -> json"
$SVS script edif_to_nextpnr.lua $SVSDIR >/tmp/min_svs.out 2>&1; tail -1 /tmp/min_svs.out
test -s /tmp/uartram.json || { echo JSON_FAIL; exit 1; }
say "3/5 nextpnr (router2, userclk 156.25MHz, seeds: $SEEDS)"
ok=0
for SEED in $SEEDS; do
  echo "--- seed $SEED ---"
  flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 \
    $NEXTPNR --router router2 --seed $SEED --chipdb $CHIPDB --xdc top_min_uc.xdc \
      --json /tmp/uartram.json --fasm /tmp/uartram_min.fasm --freq 156 >/tmp/min_npnr.out 2>&1
  rc=$?
  fmax=$(grep -iE "Max frequency for clock 'clk'" /tmp/min_npnr.out | tail -1)
  echo "  rc=$rc  $fmax"
  if [ $rc -eq 0 ] && [ -s /tmp/uartram_min.fasm ]; then ok=1; cp /tmp/uartram_min.fasm /tmp/uartram_min_seed$SEED.fasm; break; fi
done
[ $ok -eq 1 ] || { echo "NO_CONVERGE_FAIL"; grep -iE "failed to converge|overused" /tmp/min_npnr.out | tail -2; exit 1; }
test -s /tmp/uartram_min.fasm || { echo FASM_FAIL; exit 1; }
say "4/5 fasm2frames + rx-IOB patch"
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $F2F --db-root $PXDB --part $PART /tmp/uartram_min.fasm /tmp/uartram_min.frames >/tmp/min_f2f.out 2>&1 && echo "frames OK" || { echo F2F_FAIL; tail /tmp/min_f2f.out; exit 1; }
$PXPY $ROOT/uartram/patch_rx_iob.py /tmp/uartram_min.frames /tmp/uartram_min_rx.frames && mv /tmp/uartram_min_rx.frames /tmp/uartram_min.frames
say "5/5 frames2bit"
$F2B --part_file $PXDB/$PART/part.yaml --part_name $PART --frm_file /tmp/uartram_min.frames --output_file /tmp/uartram_min.bit >/tmp/min_f2b.out 2>&1 && echo "bit OK -> /tmp/uartram_min.bit" || { echo F2B_FAIL; exit 1; }
echo "MIN_DONE"
