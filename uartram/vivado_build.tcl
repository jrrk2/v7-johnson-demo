set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv calc_core.sv byte_fifo.sv top.sv
read_xdc top.xdc
set defs ""
set out /tmp/uartram_vivado.bit
if {[info exists ::env(UCDEFS)] && $::env(UCDEFS) ne ""} {
    foreach d $::env(UCDEFS) { lappend defs -verilog_define $d }
    set out /tmp/uartram_userclk_viv.bit
}
synth_design -top top -part $part {*}$defs
opt_design
place_design
route_design
report_timing_summary -file /tmp/uartram_timing.rpt
puts "RAMB18: [llength [get_cells -hier -filter {REF_NAME =~ RAMB18*}]]  RAMB36: [llength [get_cells -hier -filter {REF_NAME =~ RAMB36*}]]  LUTRAM: [llength [get_cells -hier -filter {REF_NAME =~ RAM*X*}]]  CARRY4: [llength [get_cells -hier -filter {REF_NAME =~ CARRY4*}]]"
write_bitstream -force $out
puts "WROTE $out"
puts "UARTRAM_BUILD_DONE"
