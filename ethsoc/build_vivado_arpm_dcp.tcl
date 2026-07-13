# Golden Vivado build of the RESTRUCTURED ARP responder (vc707_arpm.v: FIFO-
# boundary framing + eth_macro + arp_ctrl).  Vivado's own P&R -> tests whether
# the restructured RTL works on silicon at all, independent of the open flow.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [list arp_ctrl.sv framing_top_sgmii.sv eth_macro.sv sgmii_soc.sv eth_mac_1g.sv \
    axis_gmii_rx.sv axis_gmii_tx.sv rgmii_lfsr.sv dualmem64.sv]
read_verilog [list async_fifo.v eth_stream_conv.v]
read_verilog pcs_pma_flat.v
read_verilog vc707_arp.v
read_xdc vc707_ethsoc.xdc
read_xdc vc707_ethsoc_clocks.xdc
synth_design -top top -part $part -flatten_hierarchy rebuilt -verilog_define VC707
opt_design
place_design
route_design
report_timing_summary -file timing_arpm_gold.rpt -max_paths 3
write_checkpoint -force vc707_arpm_impl.dcp
puts "ARPM_GOLD_DONE"
