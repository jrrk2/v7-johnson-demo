set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
set ETH /home/jonathan/v7-johnson-demo/ethsoc
read_verilog -sv [list $ETH/framing_top_sgmii.sv $ETH/sgmii_soc.sv $ETH/eth_mac_1g.sv \
    $ETH/axis_gmii_rx.sv $ETH/axis_gmii_tx.sv $ETH/rgmii_lfsr.sv \
    $ETH/dualmem_widen.sv $ETH/dualmem_widen8.sv $ETH/ramb16_compat.v top_lb3.sv]
read_verilog $ETH/pcs_pma_flat.v
read_xdc lb3.xdc
read_xdc $ETH/vc707_ethsoc_clocks.xdc
synth_design -top top_lb3 -part $part -verilog_define VC707
opt_design
place_design
route_design
write_checkpoint -force lb3_golden.dcp
write_bitstream -force lb3_golden.bit
write_verilog -force -mode design lb3_netlist.v
set fp [open placement_lb3.txt w]
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE && PRIMITIVE_LEVEL != "MACRO"}] {
    set site [get_property LOC $c]
    set bel  [get_property BEL $c]
    if {$site ne "" && $bel ne ""} {
        puts $fp "$c\t$site\t$bel\t[get_property REF_NAME $c]"
    }
}
close $fp
report_timing_summary -file timing_lb3.rpt -max_paths 3
puts "LB3_BUILD_DONE"
