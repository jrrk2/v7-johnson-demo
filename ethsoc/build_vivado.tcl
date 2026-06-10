set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_ip ip/gen/gig_ethernet_pcs_pma_0/gig_ethernet_pcs_pma_0.xci
read_verilog -sv [list framing_top_sgmii.sv sgmii_soc.sv eth_mac_1g.sv \
    axis_gmii_rx.sv axis_gmii_tx.sv rgmii_lfsr.sv dualmem_widen.sv dualmem_widen8.sv]
read_verilog [list vc707_ethsoc.v picosoc_noflash.v picorv32.v simpleuart.v \
    spimemio.v progmem.v]
read_xdc vc707_ethsoc.xdc
# VC707 define selects the RAMB16 implementation in dualmem_widen*
synth_design -top top -part $part -flatten_hierarchy rebuilt -verilog_define VC707
opt_design
place_design
route_design
write_checkpoint -force vc707_ethsoc.dcp
write_bitstream -force vc707_ethsoc.bit
report_timing_summary -file timing.rpt -max_paths 3
puts "ETHSOC_BUILD_DONE"
