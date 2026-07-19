set D [expr {[info exists ::env(ETH)] ? $::env(ETH) : "/home/jonathan/v7-johnson-demo/ethsoc"}]
set H [expr {[info exists ::env(W)] ? $::env(W) : "/tmp/svs_hybrid"}]
# golden wrappers, eth_macro black-boxed (do NOT read eth_macro.sv)
foreach f {arp_ctrl framing_top_sgmii dualmem64 dualmem_widen dualmem_widen8} { read_verilog -sv $D/$f.sv }
foreach f {async_fifo ramb16_compat vc707_arp} { read_verilog $D/$f.v }
read_verilog $H/eth_macro_bb.v
synth_design -top top -part xc7vx485tffg1761-2 -flatten_hierarchy full -verilog_define VC707
write_edif -force $H/top.edf
puts "=== WRAPPERS SYNTH DONE ==="
close_design
read_edif $H/top.edf
read_edif $H/eth_macro.edf
link_design -top top -part xc7vx485tffg1761-2
read_xdc $D/vc707_ethsoc.xdc
read_xdc $D/vc707_ethsoc_clocks.xdc
puts "=== LINKED ==="
opt_design
place_design
route_design
puts [report_route_status -return_string]
write_bitstream -force $H/svs_eth_in_golden.bit
puts "=== HYBRID2_DONE ==="
