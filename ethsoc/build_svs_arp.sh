#!/bin/bash
# SVS-placed eth-arp: fully-open place+route+bitstream (no Vivado in the loop).
#   Vivado post-synth netlist (/tmp/vivado_arp.json) -> SVS place_lef (SA topo
#   place, carry anchors, control-buffer tiers, LUT1 relays) -> carry_stamp.py
#   (carry-slice completion: S/DI buffers, pin-aligned DIrt, sum-FF slots) ->
#   nextpnr-xilinx router2 -> fasm2frames (~/prjxray) -> xc7frames2bit.
# First 0-skip route + bit: 2026-07-13 (427->0 arc trajectory, see SVS repo
# commit 1d5dc85 + follow-ups).  BUFR tier OFF: fabric->BUFR.I ingress does
# not route to stamped sites in this chipdb (egress is fine) -- control nets
# ride the BUFG/fabric-replication tiers instead.
set -eu
ROOT=/home/jonathan/v7-johnson-demo
SVS=/home/jonathan/System-Verilog-suite
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2
NETLIST=${NETLIST:-/tmp/vivado_arp.json}
FLOORPLAN=${FLOORPLAN:-/tmp/virtex7_floorplan.json}

cd $SVS
eval $(opam env --switch=5.3.0) 2>/dev/null; export PATH=$HOME/.opam/5.3.0/bin:$PATH
: > /tmp/svsarp_fix.txt
echo "=== SVS place ==="
TOPO_COH_W=10 TOPO_SITE_W=300 TOPO_SITE_FRAC=0.55 TOPO_REGION_FILL=0.5 TOPO_SA_MOVES=900000 \
  TOPO_CONG_W=6 TOPO_CONG_CAP=8 TOPO_CONG_BIN=5 TOPO_LL_W=8 TOPO_LL_HCAP=5 TOPO_LL_VCAP=5 \
  TOPO_FEEDTHRU=18 TOPO_RELAY_MAXD=6 TOPO_BUF_TYPE=BUFR TOPO_BUFR_PER_REGION=0 \
  TOPO_BUFG_FANOUT=24 TOPO_BUFG_MAX=40 \
  TOPO_FIXNETS=/tmp/svsarp_fix.txt TOPO_PLACE=sa TOPO_SEED=1 \
  BELS_OUT=/tmp/svsarp_bels.txt TOPO_FT_JSON=/tmp/svsarp_ft.json \
  TOPO_STAMPED_JSON=/tmp/svsarp_stamped_ocaml.json PLACED_OUT=/tmp/svsarp_p.txt \
  $SVS/_build/default/place_lef.exe $FLOORPLAN $NETLIST 2>&1 | grep -E "FOM:|feedthroughs|carry-stamp"
echo "=== carry-slice stamp (python reference; OCaml port writes *_ocaml.json) ==="
python3 $SVS/carry_stamp.py /tmp/svsarp_ft.json /tmp/svsarp_bels.txt /tmp/svsarp_stamped.json
echo "=== route ==="
flock /tmp/nextpnr.lock env NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 NEXTPNR_SKIP_FAILED_ARCS=1 NEXTPNR_ARC_MAX_VISIT=400000 \
  $ROOT/deps/nextpnr-xilinx/build-opt/nextpnr-xilinx --router router2 \
  --chipdb $ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin --xdc $ROOT/ethsoc/r0_pins.xdc \
  --json /tmp/svsarp_stamped.json --fasm /tmp/svsarp.fasm > /tmp/svsarp_npnr.log 2>&1 \
  || { echo "NEXTPNR FAILED"; tail -5 /tmp/svsarp_npnr.log; exit 1; }
SKIPS=$(grep -ac SKIP_FAILED_ARCS /tmp/svsarp_npnr.log || true)
echo "SKIPS=$SKIPS"
[ "$SKIPS" = 0 ] || { echo "route incomplete"; grep -a SKIP_FAILED_ARCS /tmp/svsarp_npnr.log | head; exit 1; }
echo "=== bitstream ==="
GTCOMMON=$(grep -oE "GTX_COMMON_X[0-9]+Y[0-9]+" /tmp/svsarp.fasm | head -1)
[ -n "$GTCOMMON" ] && printf '%s.IBUFDS_GTE2_Y0.CLKCM_CFG\n%s.IBUFDS_GTE2_Y0.CLKRCV_TRST\n' \
  "$GTCOMMON" "$GTCOMMON" >> /tmp/svsarp.fasm
XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $HOME/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/svsarp.fasm /tmp/svsarp.frames > /tmp/svsarp_f2f.log 2>&1 \
  || { echo "F2F FAILED"; tail -5 /tmp/svsarp_f2f.log; exit 1; }
$HOME/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/svsarp.frames --output_file /tmp/svs_arp.bit \
  > /tmp/svsarp_f2b.log 2>&1 || { echo "F2B FAILED"; tail -5 /tmp/svsarp_f2b.log; exit 1; }
ls -l /tmp/svs_arp.bit | awk '{print "SVS_ARP BIT:",$5,"bytes"}'
echo "SVS_ARP_DONE"
