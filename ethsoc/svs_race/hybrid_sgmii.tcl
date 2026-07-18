set D /home/jonathan/v7-johnson-demo/ethsoc
set H3 /tmp/eb/hybrid3
# golden everything, sgmii_soc black-boxed (do NOT read sgmii_soc.sv / pcs_pma_flat.v)
read_verilog -sv [list $D/arp_ctrl.sv $D/framing_top_sgmii.sv $D/eth_mac_1g.sv \
    $D/axis_gmii_rx.sv $D/axis_gmii_tx.sv $D/rgmii_lfsr.sv $D/dualmem_widen.sv $D/dualmem_widen8.sv \
    $D/eth_macro.sv $D/dualmem64.sv]
read_verilog [list $D/async_fifo.v $D/ramb16_compat.v $D/eth_stream_conv.v $D/vc707_arp.v]
read_verilog $H3/sgmii_soc_bb.v
synth_design -top top -part xc7vx485tffg1761-2 -flatten_hierarchy full -verilog_define VC707
write_edif -force $H3/top.edf
puts "=== WRAPPERS SYNTH DONE ==="
close_design
read_edif $H3/top.edf
read_edif $H3/sgmii_soc.edf
link_design -top top -part xc7vx485tffg1761-2
read_xdc $D/vc707_ethsoc.xdc
read_xdc $D/vc707_ethsoc_clocks.xdc
puts "=== LINKED ==="
opt_design
place_design
route_design
puts [report_route_status -return_string]
write_bitstream -force $H3/svs_sgmii_in_golden.bit
puts "=== HYBRID3_DONE ==="
