# Golden Vivado build of the processor-free eth<->UART hex bridge
# (vc707_arp.v).  Same clocking / pins / eth stack as the flat50 SoC, but
# picosoc/picorv32/spimemio/progmem are replaced by the two loopback FSMs, so
# the netlist is far smaller -> smaller pip search space for the open flow.
# Produces the vendored artifacts for the R0 open flow: flat netlist +
# placement dump + golden bit.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [list arp_ctrl.sv framing_top_sgmii.sv sgmii_soc.sv eth_mac_1g.sv \
    axis_gmii_rx.sv axis_gmii_tx.sv rgmii_lfsr.sv dualmem_widen.sv dualmem_widen8.sv]
read_verilog pcs_pma_flat.v
read_verilog vc707_arp.v
read_xdc vc707_ethsoc.xdc
read_xdc vc707_ethsoc_clocks.xdc
synth_design -top top -part $part -flatten_hierarchy rebuilt -verilog_define VC707
opt_design
place_design
route_design
write_checkpoint -force vc707_arp.dcp
write_bitstream -force vc707_arp.bit
write_verilog -force -mode design vc707_arp_netlist.v
set fp [open placement_arp.txt w]
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE && PRIMITIVE_LEVEL != "MACRO"}] {
    set site [get_property LOC $c]
    set bel  [get_property BEL $c]
    if {$site ne "" && $bel ne ""} {
        puts $fp "$c\t$site\t$bel\t[get_property REF_NAME $c]"
    }
}
close $fp
report_utilization -file util_arp.rpt
report_timing_summary -file timing_arp.rpt -max_paths 3
puts "ETHLOOP_BUILD_DONE"
