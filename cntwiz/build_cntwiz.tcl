set part xc7vx485tffg1761-2
create_project -force cntwiz_proj /tmp/cntwiz_proj -part $part
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {200.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50.000} \
] [get_ips clk_wiz_0]
set_property GENERATE_SYNTH_CHECKPOINT FALSE [get_files [get_property IP_FILE [get_ips clk_wiz_0]]]
generate_target all [get_ips clk_wiz_0]
read_verilog cnt_top.v
read_xdc cnt.xdc
synth_design -top cnt_top -part $part -flatten_hierarchy rebuilt
opt_design
place_design
route_design
write_checkpoint -force cntwiz.dcp
write_bitstream -force cntwiz.bit
write_verilog -force cntwiz_netlist.v
set fp [open placement_cntwiz.txt w]
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE}] {
    set site [get_property SITE $c]
    set bel  [get_property BEL  $c]
    if {$site ne "" && $bel ne ""} {
        puts $fp "[get_property NAME $c]\t$site\t$bel\t[get_property REF_NAME $c]"
    }
}
close $fp
puts "CNTWIZ_DONE"
