# SVS silicon-debug kit (2026-07-18 campaign: 15 bugs -> 25/25 ARP)

## xsim RTL-vs-netlist lockstep races
Per module: emit gate-mapped EDIF (svs_<mod>.lua) -> Vivado link +
write_verilog -mode funcsim -> rename module -> race vs RTL under LFSR
stimulus (tb_<mod>.v, X-tolerant compare). Closed-loop variants inject a
canned ARP request via eth_player.v (an eth_macro stand-in driving the
FIFO gray/addr/data interface) and compare the captured reply words:
  tb_mac   - eth_mac_1g (found the dead TX CRC)
  tb_glue  - rx packer / tx unpacker / async_fifo halves (frozen gray ptrs)
  tb_arp   - arp_ctrl random race;  tb_loop - closed loop (target_ip loss)
  tb_frame - framing_top, eth blackboxed (dead casez register mux)
  tb_top   - gate-mapped top;  tb_full - whole production flatten
Blackboxing needs port dirs in xilinx_lef/xil_primitive_ports.json
(eth_macro / framing_top_sgmii / arp_ctrl entries - json is GITIGNORED,
re-add after regeneration).

## silicon bisection hybrids (golden Vivado shell + one SVS EDIF)
hybrid.tcl(eth_macro) / hybrid_sgmii.tcl / hybrid4.tcl(framing) /
hybrid5.tcl(arp_ctrl) + *_bb.v stubs. read_edif child file MUST be
named <topcell>.edf.

## full open build
arp_passthru.lua -> /tmp/eb/arp_passthru.edf; pnr_passthru.tcl -> bit.
MUST read vc707_flat_clocks.xdc (flat-name gt_txoutclk + async clock
groups) - omitting it leaves the 125MHz domain untimed: the final bug.

## netlist forensics
netdiff.py (structural EDIF-vs-verilog diff), dump.tcl + drvcmp.py
(authoritative per-pin driver maps via get_pins -leaf, both sides linked
in Vivado - found data_valid==GND among 9975 pins).
