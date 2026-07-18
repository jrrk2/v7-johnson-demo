set D /home/jonathan/v7-johnson-demo/ethsoc
set H /tmp/eb/hybrid5
read_verilog -sv [list $D/framing_top_sgmii.sv $D/sgmii_soc.sv $D/eth_mac_1g.sv \
    $D/axis_gmii_rx.sv $D/axis_gmii_tx.sv $D/rgmii_lfsr.sv $D/dualmem_widen.sv $D/dualmem_widen8.sv \
    $D/eth_macro.sv $D/dualmem64.sv]
read_verilog [list $D/async_fifo.v $D/ramb16_compat.v $D/eth_stream_conv.v $D/pcs_pma_flat.v $D/vc707_arp.v]
read_verilog $H/arp_bb.v
synth_design -top top -part xc7vx485tffg1761-2 -flatten_hierarchy full -verilog_define VC707
write_edif -force $H/top.edf
close_design
read_edif $H/top.edf
read_edif $H/arp_ctrl.edf
link_design -top top -part xc7vx485tffg1761-2
read_xdc $D/vc707_ethsoc.xdc
read_xdc $D/vc707_ethsoc_clocks.xdc
opt_design
place_design
route_design
puts [report_route_status -return_string]
write_bitstream -force $H/svs_arp_in_golden.bit
puts "=== HYBRID5_DONE ==="
