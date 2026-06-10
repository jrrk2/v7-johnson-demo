#!/bin/bash
# 100% open-flow build of PicoSoC (picorv32 + simpleuart + BRAM RAM + LUT-ROM
# progmem) on the VC707 200 MHz LVDS sysclk (E19/E18), no MMCM, no Vivado.
#   riscv-gcc firmware -> progmem.v -> yosys synth_xilinx -> nextpnr-xilinx
#   -> fasm -> fasm2frames -> rx IOB patch (AU33 prjxray gap) -> bit
# Output: /tmp/picosoc_open.bit
# env: SEED (default 1), FREQ (default 200)
set -u
ROOT=/home/jonathan/v7-johnson-demo
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
F2F=$ROOT/deps/prjxray/utils/fasm2frames.py
F2B=$ROOT/deps/prjxray/build/tools/xc7frames2bit
PXDB=$ROOT/deps/prjxray/database/virtex7
PART=xc7vx485tffg1761-2
YOSYS=$(ls $HOME/oss-cad-suite/bin/yosys $HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys 2>/dev/null | head -1)
YOSYS=${YOSYS:-yosys}
SEED=${SEED:-1}
FREQ=${FREQ:-100}
cd $ROOT/picosoc
say(){ echo "===== $* ====="; }

say "1/6 firmware (rv32i, clkdiv 867 = 115200 @ 100 MHz)"
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib \
  -o firmware.elf -Wl,-Bstatic,-T,sections.lds,--strip-debug start.s firmware.c || exit 1
riscv64-unknown-elf-objcopy -O binary firmware.elf firmware.bin
python3 bin2verilog.py firmware.bin > progmem.v || exit 1

say "2/6 yosys synth_xilinx"
$YOSYS -p "read_verilog -sv vc707_picosoc.v picosoc_noflash.v picorv32.v simpleuart.v spimemio.v progmem.v; \
  hierarchy -top top; synth_xilinx -flatten -family xc7; write_json /tmp/picosoc_open.json" \
  >/tmp/picosoc_synth.log 2>&1 || { echo "SYNTH FAILED"; tail -15 /tmp/picosoc_synth.log; exit 1; }
grep -E "^\s+[0-9]+\s+RAMB36E1" /tmp/picosoc_synth.log | tail -1

say "3/6 nextpnr-xilinx (router2, seed $SEED, flock-serialized, $FREQ MHz)"
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 \
  $NEXTPNR --router router2 --seed $SEED --chipdb $CHIPDB --xdc vc707_picosoc.xdc \
    --json /tmp/picosoc_open.json --fasm /tmp/picosoc_open.fasm --freq $FREQ \
    >/tmp/picosoc_npnr.log 2>&1
echo "nextpnr exit=$?"
grep -iE "Max frequency|Routing complete|failed|unrouted|error" /tmp/picosoc_npnr.log | tail -5
test -s /tmp/picosoc_open.fasm || { echo "FASM FAILED"; exit 1; }

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
