set D /home/jonathan/v7-johnson-demo/ethsoc
set H /tmp/eb/hybrid4
read_verilog -sv [list $D/arp_ctrl.sv]
read_verilog [list $D/vc707_arp.v]
read_verilog $H/framing_bb.v
synth_design -top top -part xc7vx485tffg1761-2 -flatten_hierarchy full -verilog_define VC707
write_edif -force $H/top.edf
close_design
read_edif $H/top.edf
read_edif $H/framing_top_sgmii.edf
link_design -top top -part xc7vx485tffg1761-2
read_xdc $D/vc707_ethsoc.xdc
read_xdc $D/vc707_ethsoc_clocks.xdc
opt_design
place_design
route_design
puts [report_route_status -return_string]
write_bitstream -force $H/svs_framing_in_golden.bit
puts "=== HYBRID4_DONE ==="
