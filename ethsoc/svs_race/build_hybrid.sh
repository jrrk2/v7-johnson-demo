#!/bin/bash
# Silicon-bisection hybrid builder: golden Vivado shell + ONE SVS-synthesized
# layer, linked as an EDIF black-box.  Each layer isolates a slice of the eth
# stack (used to localize the 15-bug SVS campaign; all 5 now pass 15/15 ARP).
#
#   build_hybrid.sh <layer>
#     ethmacro  golden top+framing+arp, SVS eth_macro          (svs_eth_in_golden.bit)
#     sgmii     golden everything, SVS sgmii_soc               (svs_sgmii_in_golden.bit)
#     framing   golden top+arp, SVS framing_top_sgmii          (svs_framing_in_golden.bit)
#     arp       golden eth stack, SVS arp_ctrl                 (svs_arp_in_golden.bit)
#
# Env: SVS (suite repo), VIVADO, ETH (ethsoc dir), W (work dir), OUT unused
# (bit lands in $W).  Flash with openFPGALoader; arping 192.168.1.100.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ETH=${ETH:-$(cd "$HERE/.." && pwd)}
SVS=${SVS:-$HOME/System-Verilog-suite}
VIVADO=${VIVADO:-/opt/Xilinx/Vivado/2020.1/bin/vivado}
LAYER=${1:?usage: build_hybrid.sh <ethmacro|sgmii|framing|arp>}
W=${W:-/tmp/svs_hybrid_$LAYER}
mkdir -p "$W"

case "$LAYER" in
  ethmacro) RECIPE=svs_ethmacro.lua; EDIF=eth_macro.edf;        BB=eth_macro_bb.v;        TCL=hybrid.tcl ;;
  sgmii)    RECIPE=svs_sgmii.lua;    EDIF=sgmii_soc.edf;        BB=sgmii_soc_bb.v;        TCL=hybrid_sgmii.tcl ;;
  framing)  RECIPE=svs_framing.lua;  EDIF=framing_top_sgmii.edf; BB=framing_bb.v;         TCL=hybrid4.tcl ;;
  arp)      RECIPE=svs_arp.lua;      EDIF=arp_ctrl.edf;         BB=arp_bb.v;             TCL=hybrid5.tcl ;;
  *) echo "unknown layer '$LAYER'" >&2; exit 2 ;;
esac

echo "=== 1. SVS synth: $RECIPE -> $W/$EDIF ==="
( cd "$SVS" && MEMLOWER_FPGA=1 FPGA_LEC_NAMES=1 W="$W" \
    ./_build/default/sv_suite.exe script "$HERE/$RECIPE" 2>&1 | grep -aE 'WROTE|gate_map|PASS' | tail -2 )
[ -s "$W/$EDIF" ] || { echo "recipe produced no $EDIF" >&2; exit 1; }
cp "$HERE/$BB" "$W/$BB"

echo "=== 2. Vivado: golden wrappers + link $EDIF + P&R ==="
( cd "$W" && ETH="$ETH" W="$W" "$VIVADO" -mode batch -source "$HERE/$TCL" \
    -journal "$W/h.jou" -log "$W/h.log" 2>&1 | grep -aE 'HYBRID|DONE|Route|Failed Nets|ERROR|undriven' | tail -6 )
BIT=$(ls "$W"/*.bit 2>/dev/null | head -1)
echo "HYBRID $LAYER BIT: ${BIT:-<none>}"
