#!/bin/bash
# Open-flow build of the loopback rung-3 (top_lb3): JTAG<->SGMII eth triage.
# Same hybrid R0 flow as ethsoc/build_r0.sh (Vivado placement stamped, nextpnr
# routes, GT config frames spliced from the golden bitstream) -- a small
# eth+jtag benchmark for the open flow.  Its system clock is board-derived
# (MMCM RST=0), so the fabric/JTAG come up independent of the GT link.
#   Output: /tmp/lb3_ethjtag.bit    Status over JTAG: loopback/jtag_lb3.tcl
set -eu
ROOT=/home/jonathan/v7-johnson-demo
LB=$ROOT/loopback
ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$ROOT/deps/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

# 1. yosys: flat Vivado netlist -> nextpnr json (RAM32M/64M -> structural, same
#    as ethsoc; GT/PCS-PMA blackboxed via gt_stubs.v).
$YOSYS -p "
read_verilog -lib +/xilinx/cells_sim.v
read_verilog -lib +/xilinx/cells_xtra.v
read_verilog -lib $ETH/xil_bb.v
read_verilog -lib $ETH/gt_stubs.v
delete RAM32M RAM64M
read_verilog $ETH/ram_m_structural.v
read_verilog $LB/lb3_netlist_y.v
hierarchy -top top_lb3
flatten
clean
delete t:\$scopeinfo
blackbox =* top_lb3 %d
stat
write_json /tmp/lb3.json
" > /tmp/lb3_yosys.log 2>&1 || { echo "YOSYS FAILED"; tail -20 /tmp/lb3_yosys.log; exit 1; }
echo "yosys OK"

# 2. stamp the vendored Vivado placement (BEL attrs + routethru LUT1s)
python3 $ETH/stamp_placement.py /tmp/lb3.json $LB/placement_lb3.txt /tmp/lb3_stamped.json

# 3. nextpnr: route the stamped placement (CO/5FF contention allowed for the
#    Vivado import; see arch_place.cc).
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=2000000 NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  $NEXTPNR --chipdb $CHIPDB --xdc $LB/lb3.xdc --json /tmp/lb3_stamped.json \
    --fasm /tmp/lb3.fasm --freq 50 --router router2 --placer sa \
    > /tmp/lb3_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -25 /tmp/lb3_npnr.log; exit 1; }
grep -iE "Max frequency|Routing complete|failed|unrouted" /tmp/lb3_npnr.log | tail -4
echo "nextpnr OK"

# 4. fasm2frames
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $ROOT/deps/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/lb3.fasm /tmp/lb3.frames > /tmp/lb3_f2f.log 2>&1 \
  && echo "frames OK" || { echo "F2F FAILED"; tail /tmp/lb3_f2f.log; exit 1; }

# 5. splice the GT config frames from the golden bitstream (GT IP is identical
#    to ethsoc: X0Y0 GTXE2, 125 MHz SGMII refclk).
python3 $ETH/splice_gt_frames.py $ETH/golden_ethsoc.bits /tmp/lb3.frames /tmp/lb3_spliced.frames

# 6. frames2bit
$ROOT/deps/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/lb3_spliced.frames --output_file /tmp/lb3_ethjtag.bit \
  > /tmp/lb3_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; tail /tmp/lb3_f2b.log; exit 1; }
ls -l /tmp/lb3_ethjtag.bit | awk '{print "LB3 ETH+JTAG BIT:",$5,"bytes"}'
echo "LB3_OPEN_DONE"
