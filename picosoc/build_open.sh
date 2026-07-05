#!/bin/bash
# 100% open-flow build of PicoSoC (picorv32 + simpleuart + BRAM RAM + LUT-ROM
# progmem) on the VC707 200 MHz LVDS sysclk (E19/E18), no MMCM, no Vivado.
#   riscv-gcc firmware -> progmem.v -> yosys synth_xilinx -> nextpnr-xilinx
#   -> fasm -> fasm2frames -> rx IOB patch (AU33 prjxray gap) -> bit
# Output: /tmp/picosoc_open.bit
# env: SEED (default: sweep until routed), FREQ (default 25 = the real MMCM
#      cpu_clk; a higher --freq over-constrains and stresses the router).
set -u
# Repo root = the parent of this script's dir (picosoc/), so the build works
# from any checkout on Linux or macOS -- no hardcoded paths.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
F2F=$ROOT/deps/prjxray/utils/fasm2frames.py
F2B=$ROOT/deps/prjxray/build/tools/xc7frames2bit
PXDB=$ROOT/deps/prjxray/database/virtex7
PART=xc7vx485tffg1761-2
YOSYS=$(ls $HOME/oss-cad-suite/bin/yosys $HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys 2>/dev/null | head -1)
YOSYS=${YOSYS:-yosys}
# RISC-V toolchain: brew's riscv tap is riscv64-unknown-elf-*; some installs use
# riscv64-elf-*.  Override RISCV_PREFIX if yours differs.
RISCV_PREFIX=${RISCV_PREFIX:-$(for p in riscv64-unknown-elf riscv64-elf riscv-none-elf; do command -v $p-gcc >/dev/null 2>&1 && { echo $p; break; }; done)}
RISCV_PREFIX=${RISCV_PREFIX:-riscv64-unknown-elf}
# flock serialises concurrent nextpnr runs (shared chipdb); it's Linux-only and
# unnecessary for a single build, so use it only when present (skip on macOS).
if command -v flock >/dev/null 2>&1; then LOCK="flock /tmp/nextpnr.lock"; else LOCK=""; fi
# FREQ = the real cpu_clk the MMCM produces (200 MHz * 5 / 40 = 25 MHz).  The
# sysclk is pinned to 200 MHz by the XDC; --freq only sets the *default* for the
# derived cpu_clk/bs_drck.  Asking for 100 MHz there just over-constrains a clock
# that physically runs at 25 -- reports a bogus "FAIL at 100 MHz" and drives a
# tighter, more congested placement that can go unroutable.
FREQ=${FREQ:-25}
# SEED: if the caller pins one, use just that; otherwise sweep until one routes
# (nextpnr placement is seed-sensitive and a congested SoC can miss on any given
# seed -- exactly like the calc target in the top-level Makefile).
if [ -n "${SEED:-}" ]; then SEEDS=$SEED; else SEEDS=${SEEDS:-"1 2 3 4 42 7 12 19"}; fi
cd $ROOT/picosoc
say(){ echo "===== $* ====="; }

say "1/6 firmware (rv32i, clkdiv 216 = 115200 @ 25 MHz MMCM cpu_clk)"
${RISCV_PREFIX}-gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib \
  -o firmware.elf -Wl,-Bstatic,-T,sections.lds,--strip-debug start.s firmware.c || exit 1
${RISCV_PREFIX}-objcopy -O binary firmware.elf firmware.bin
python3 bin2verilog.py firmware.bin > progmem.v || exit 1

say "2/6 yosys synth_xilinx"
$YOSYS -p "read_verilog -sv vc707_picosoc.v picosoc_noflash.v picorv32.v simpleuart.v spimemio.v progmem.v; \
  hierarchy -top top; synth_xilinx -flatten -family xc7; write_json /tmp/picosoc_open.json" \
  >/tmp/picosoc_synth.log 2>&1 || { echo "SYNTH FAILED"; tail -15 /tmp/picosoc_synth.log; exit 1; }
grep -E "^\s+[0-9]+\s+RAMB36E1" /tmp/picosoc_synth.log | tail -1

say "3/6 nextpnr-xilinx (router2, freq $FREQ MHz, seeds: $SEEDS)"
rm -f /tmp/picosoc_open.fasm
for s in $SEEDS; do
  $LOCK env NEXTPNR_ARC_MAX_VISIT=2000000 \
    $NEXTPNR --router router2 --seed $s --chipdb $CHIPDB --xdc vc707_picosoc.xdc \
      --json /tmp/picosoc_open.json --fasm /tmp/picosoc_open.fasm.s$s --freq $FREQ \
      >/tmp/picosoc_npnr.log 2>&1
  rc=$?
  fmax=$(grep "Max frequency for clock 'cpu_clk'" /tmp/picosoc_npnr.log | grep -oE "[0-9]+\.[0-9]+" | head -1)
  if [ $rc -eq 0 ] && [ -s /tmp/picosoc_open.fasm.s$s ]; then
    echo "  seed $s: routed  (cpu_clk ${fmax:-?} MHz, target $FREQ)"
    mv /tmp/picosoc_open.fasm.s$s /tmp/picosoc_open.fasm; break
  fi
  echo "  seed $s: unroutable (exit $rc) -- trying next"
  rm -f /tmp/picosoc_open.fasm.s$s
done
grep -iE "Max frequency|Routing complete|failed|unrouted|error" /tmp/picosoc_npnr.log | tail -3
test -s /tmp/picosoc_open.fasm || { echo "FASM FAILED (no seed in '$SEEDS' routed; add more via SEEDS='...')"; exit 1; }

say "4/6 fasm2frames"
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $F2F --db-root $PXDB --part $PART \
  /tmp/picosoc_open.fasm /tmp/picosoc_open.frames >/tmp/picosoc_f2f.log 2>&1 \
  && echo "frames OK" || { echo "F2F FAILED"; tail /tmp/picosoc_f2f.log; exit 1; }

say "5/6 patch rx IOB (prjxray AU33 LVCMOS18 input segbit gap)"
$PXPY $ROOT/uartram/patch_rx_iob.py /tmp/picosoc_open.frames /tmp/picosoc_open_rx.frames \
  && mv /tmp/picosoc_open_rx.frames /tmp/picosoc_open.frames

# (led[4]/AR35 SING-tile fix now lives in the prjxray DB itself:
#  ppips_lioi_sing.db declares the OLOGIC route-thru features bit-free —
#  see database/virtex7/FIXES.md.  patch_led4_iob.py kept for reference.)

say "6/6 frames2bit"
$F2B --part_file $PXDB/$PART/part.yaml --part_name $PART \
  --frm_file /tmp/picosoc_open.frames --output_file /tmp/picosoc_open.bit \
  >/tmp/picosoc_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; exit 1; }
ls -l /tmp/picosoc_open.bit | awk '{print "OPEN PICOSOC BIT:",$5,"bytes"}'
echo "PICOSOC_OPEN_DONE"
