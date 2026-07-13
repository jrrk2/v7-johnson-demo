set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
set IBEX /home/jonathan/v7-johnson-demo/ibexsoc
set PRIM $IBEX/vendor/lowrisc_ip/ip/prim/rtl
set_property include_dirs [list $PRIM] [current_fileset]
read_verilog -sv [list $PRIM/prim_util_pkg.sv $PRIM/prim_count_pkg.sv \
    $PRIM/prim_count.sv $PRIM/prim_fifo_sync_cnt.sv $PRIM/prim_fifo_sync.sv \
    $IBEX/rtl/system/uart.sv top_lb.sv]
read_xdc lb.xdc
synth_design -top top_lb -part $part -include_dirs $PRIM
opt_design
place_design
route_design
write_checkpoint -force lb_golden.dcp
write_bitstream -force lb_golden.bit
write_verilog -force -mode design lb_netlist.v
set fp [open placement_lb.txt w]
foreach c [get_cells -hierarchical -filter {IS_PRIMITIVE && PRIMITIVE_LEVEL != "MACRO"}] {
    set site [get_property LOC $c]
    set bel  [get_property BEL $c]
    if {$site ne "" && $bel ne ""} {
        puts $fp "$c\t$site\t$bel\t[get_property REF_NAME $c]"
    }
}
close $fp
report_timing_summary -file timing_lb.rpt -max_paths 3
puts "LB_BUILD_DONE"
