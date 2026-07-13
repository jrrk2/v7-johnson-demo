# Regression build: same sources as the open flow (incl. the Q31->Q
# rewritten pcs_pma_flat.v implementation netlist instead of the IP) but
# through the Vivado backend.  Validates the netlist/RTL alterations on HW.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [list framing_top_sgmii.sv sgmii_soc.sv eth_mac_1g.sv \
    axis_gmii_rx.sv axis_gmii_tx.sv rgmii_lfsr.sv dualmem_widen.sv dualmem_widen8.sv]
read_verilog pcs_pma_flat.v
read_verilog [list vc707_ethsoc.v picosoc_noflash.v picorv32.v simpleuart.v \
    spimemio.v progmem.v]
read_xdc vc707_ethsoc.xdc
read_xdc vc707_ethsoc_clocks.xdc
synth_design -top top -part $part -flatten_hierarchy rebuilt -verilog_define VC707 -verilog_define CLK125 -verilog_define LED_DEBUG
opt_design
place_design
route_design
write_checkpoint -force vc707_ethsoc_led.dcp
write_bitstream -force vc707_ethsoc_led.bit
report_timing_summary -file timing_led.rpt -max_paths 3
puts "ETHSOC_LED_BUILD_DONE"
write_verilog -force vc707_ethsoc_led_netlist.v
set fp [open placement_led.txt w]
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE}] {
    set site [get_property SITE $c]
    set bel  [get_property BEL  $c]
    if {$site ne "" && $bel ne ""} {
        puts $fp "[get_property NAME $c]\t$site\t$bel\t[get_property REF_NAME $c]"
    }
}
close $fp
puts "LED_EXTRACT_DONE"
