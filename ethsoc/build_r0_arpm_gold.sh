#!/bin/bash
# Macro-merge open flow pilot: reflectm = fresh yosys user logic (word-level
# MAC-swap reflector, msoc FIFO halves) + frozen Vivado eth_macro.
#   yosys (user synth + macro netlist pass-through)
#   -> stamp macro placement only (placement_macro_gold.txt; user cells placed by
#      nextpnr SA)
#   -> nextpnr with --fixed-routes eth_macro_prefixed.routes (macro-internal
#      routing locked; requires the canonicalWireId + normalised-net-name
#      patches in nextpnr applyFixedRoutes)
#   -> fasm (+ IBUFDS_GTE2 defaults) -> frames -> bit (GT from DB, no splice)
set -eu
ROOT=/home/jonathan/v7-johnson-demo
ETH=$ROOT/ethsoc
YOSYS=${YOSYS:-$HOME/OpenROAD-flow-scripts/tools/install/yosys/bin/yosys}
NEXTPNR=$ROOT/deps/nextpnr-xilinx/build/nextpnr-xilinx
CHIPDB=$ROOT/deps/nextpnr-xilinx/xilinx/xc7vx485t.bin
PXPY=$ROOT/deps/prjxray/env/bin/python
PXDB=$HOME/prjxray/database/virtex7
PART=xc7vx485tffg1761-2

# regenerate the frozen eth-block netlist (framing_top_sgmii) from the golden
# write_verilog dump: patch + EM_-prefix internals (top stays framing_top_sgmii)
python3 $ETH/make_eth_gold_ym.py $ETH/eth_gold_raw.v $ETH/eth_gold_ym.v \
  || { echo "MAKE_YM FAILED"; exit 1; }

$YOSYS $ETH/r0_arpm_gold.ys > /tmp/r0_arpm_yosys.log 2>&1 \
  || { echo "YOSYS FAILED"; tail -20 /tmp/r0_arpm_yosys.log; exit 1; }
python3 $ETH/merge_json_modules.py /tmp/arpm_user.json /tmp/arpm_macro.json /tmp/arpm_pre.json
$YOSYS $ETH/r0_arpm_merge.ys > /tmp/r0_arpm_merge.log 2>&1 \
  || { echo "YOSYS MERGE FAILED"; tail -20 /tmp/r0_arpm_merge.log; exit 1; }
echo "yosys OK"

# macro placement only (u_macro/* names match yosys's flattened u_macro.*)
# macro instance path in THIS design: framing_top instance 'eth' -> eth_macro1
# ROUTES_FILE override: default = full golden lock; backbone-only cpu_clk variant
# (/tmp/routes_cpuclk_backbone.txt) drops cpu_clk's leaf/last-mile so the router
# rebuilds the cpu_clk leaf to the ACTUAL fresh-FF placement -- golden's leaf
# targets golden's arp_ctrl region, leaving our fresh clock sinks un-hookable
# (235 'could not hook sink ...CK of cpu_clk' -> fresh FFs never clock -> reset stuck).
cp "${ROUTES_FILE:-$ETH/eth_macro_gold.routes}" /tmp/eth_macro_arpm.routes
cp $ETH/placement_macro_gold.txt /tmp/placement_arpm.txt   # full eth/* cell names

# Pin the CPU-domain clock cells to their GOLDEN sites.  We lock golden cpu_clk
# routing (backbone captured in eth_macro_gold.routes), so its MMCM/BUFG sources
# MUST sit where golden put them or the fixed cpu_clk distribution reads from an
# empty CMT/BUFG and arp_ctrl never clocks (no ARP reply).  Ground truth from the
# frozen routes: cpu_clk rides GCLK16 (= BUFGCTRL_X0Y16), sysclk rides GCLK17
# (= BUFGCTRL_X0Y17); eth clocks are GCLK0-4 (BUFGCTRL_X0Y0-4).
#   golden: cpu_mmcm=MMCME2_ADV_X0Y6, cpu_bufg=BUFGCTRL_X0Y16, sysclk_bufg=X0Y17.
printf 'cpu_mmcm\tMMCME2_ADV_X0Y6\tMMCME2_ADV.MMCME2_ADV\tMMCME2_ADV\n' >> /tmp/placement_arpm.txt
printf 'cpu_bufg\tBUFGCTRL_X0Y16\tBUFGCTRL.BUFGCTRL\tBUFGCTRL\n'       >> /tmp/placement_arpm.txt
printf 'sysclk_bufg\tBUFGCTRL_X0Y17\tBUFGCTRL.BUFGCTRL\tBUFGCTRL\n'   >> /tmp/placement_arpm.txt

python3 $ETH/stamp_placement.py /tmp/r0_arpm.json /tmp/placement_arpm.txt /tmp/r0_arpm_stamped.json /tmp/eth_macro_arpm.routes

PIP_BLACKLIST=${PIP_BLACKLIST:-$ROOT/ibexsoc/openflow/pip_blacklist_int_r_bounce.txt}
flock /tmp/nextpnr.lock env NEXTPNR_ARC_MAX_VISIT=100000000 ${NEXTPNR_EXTRA_ENV:+$NEXTPNR_EXTRA_ENV} NEXTPNR_ALLOW_CO_5FF_CONTENTION=1 \
  NEXTPNR_PIP_BLACKLIST=$PIP_BLACKLIST \
  $NEXTPNR --chipdb $CHIPDB --xdc $ETH/r0_pins.xdc --json /tmp/r0_arpm_stamped.json \
    --fixed-routes /tmp/eth_macro_arpm.routes \
    --fasm /tmp/r0_arpm.fasm --write /tmp/r0_arpm_routed.json --freq 50 --router router2 --placer sa \
    --ignore-loops \
    > /tmp/r0_arpm_npnr.log 2>&1 || { echo "NEXTPNR FAILED"; tail -25 /tmp/r0_arpm_npnr.log; exit 1; }
grep -iE "Max frequency|Routing complete|failed|unrouted|fixed-routes" /tmp/r0_arpm_npnr.log | tail -6
echo "nextpnr OK"

# inject the two always-on IBUFDS_GTE2 refclk-buffer defaults nextpnr omits
GTCOMMON=$(grep -oE "GTX_COMMON_X[0-9]+Y[0-9]+" /tmp/r0_arpm.fasm | head -1)
cp /tmp/r0_arpm.fasm /tmp/r0_arpm_final.fasm
if [ -n "$GTCOMMON" ]; then
  printf '%s.IBUFDS_GTE2_Y0.CLKCM_CFG\n%s.IBUFDS_GTE2_Y0.CLKRCV_TRST\n' "$GTCOMMON" "$GTCOMMON" \
    >> /tmp/r0_arpm_final.fasm
  echo "injected IBUFDS_GTE2 defaults for $GTCOMMON"
fi

# Overlay golden LUT INITs onto the stamped hard-macro slices: nextpnr's
# X_ORIG_PORT->INIT permutation mis-emits ~15 A1..A5-swapped frozen LUTs (wrong
# function).  The macro is a copy of golden config, so splice golden's exact
# INITs (gold_b2f.fasm = bit2fasm of the golden vc707_arpm.bit).
python3 $ETH/splice_macro_luts.py /tmp/r0_arpm_final.fasm $ETH/gold_b2f.fasm /tmp/placement_arpm.txt /tmp/r0_arpm_spliced.fasm \
  && mv /tmp/r0_arpm_spliced.fasm /tmp/r0_arpm_final.fasm

# Wholesale-stamp golden CONFIG for frozen structure nextpnr can't reproduce from
# fixed-routes:  clock spine/leaf (routeClock picks wrong GCLK tracks + reversed
# spine direction), BRAM (RAMB36 upper/lower ADDR routed via fabric IMUX instead
# of the internal CASCINTOP/CASCINBOT cascade), and every pure-eth + Vivado
# route-through CLB slice (FF ZINI/ZRST/mux, LUT INIT, SRL DI1MUX cascade).  Only
# slices holding a FRESH cell are protected -- a pure slice has no fresh cell, so
# the golden slice bits are exactly correct.
python3 $ETH/gen_stampable_slices.py /tmp/r0_arpm_routed.json $ETH/gold_b2f.fasm \
  $PXDB/xc7vx485t/tilegrid.json /tmp/stampable_slices.txt
python3 $ETH/splice_frozen_tiles.py /tmp/r0_arpm_final.fasm $ETH/gold_b2f.fasm \
  /tmp/r0_arpm_spliced.fasm /tmp/stampable_slices.txt \
  && mv /tmp/r0_arpm_spliced.fasm /tmp/r0_arpm_final.fasm

XRAY_ALLOW_MISSING_FEATURES=1 $PXPY $HOME/prjxray/utils/fasm2frames.py \
  --db-root $PXDB --part $PART /tmp/r0_arpm_final.fasm /tmp/r0_arpm.frames > /tmp/r0_arpm_f2f.log 2>&1 \
  && echo "frames OK (GT from DB, no splice)" || { echo "F2F FAILED"; tail /tmp/r0_arpm_f2f.log; exit 1; }

$HOME/prjxray/build/tools/xc7frames2bit --part_file $PXDB/$PART/part.yaml \
  --part_name $PART --frm_file /tmp/r0_arpm.frames --output_file /tmp/r0_arpm.bit \
  > /tmp/r0_arpm_f2b.log 2>&1 && echo "bit OK" || { echo "F2B FAILED"; tail /tmp/r0_arpm_f2b.log; exit 1; }
ls -l /tmp/r0_arpm.bit | awk '{print "ARPM BIT:",$5,"bytes"}'
echo "R0_ARPM_DONE"
