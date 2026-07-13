# 50 MHz single-domain variant (no CLK125): cpu_clk = sysclk-fed MMCM /20,
# eth_int_clk = cpu_clk; MAC handles the slow processor by design.  Adds
# the BSCANE2 USER1 debug register.  Produces the vendored artifacts for
# the R0 open flow: flat netlist + placement dump + golden bit.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [list framing_top_sgmii.sv sgmii_soc.sv eth_mac_1g.sv \
    axis_gmii_rx.sv axis_gmii_tx.sv rgmii_lfsr.sv dualmem_widen.sv dualmem_widen8.sv]
read_verilog pcs_pma_flat.v
read_verilog [list vc707_ethsoc.v picosoc_noflash.v picorv32.v simpleuart.v \
    spimemio.v progmem.v]
read_xdc vc707_ethsoc.xdc
read_xdc vc707_ethsoc_clocks.xdc
synth_design -top top -part $part -flatten_hierarchy rebuilt -verilog_define VC707 -verilog_define NO_JTAG
opt_design
place_design
route_design
write_checkpoint -force vc707_ethsoc_flat50.dcp
write_bitstream -force vc707_ethsoc_flat50.bit
write_verilog -force -mode design vc707_ethsoc_flat50_netlist.v
set fp [open placement_flat50.txt w]
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE && PRIMITIVE_LEVEL != "MACRO"}] {
    set site [get_property LOC $c]
    set bel  [get_property BEL $c]
    if {$site ne "" && $bel ne ""} {
        puts $fp "$c\t$site\t$bel\t[get_property REF_NAME $c]"
    }
}
close $fp
report_timing_summary -file timing_flat50.rpt -max_paths 3
puts "ETHSOC_FLAT50_BUILD_DONE"
