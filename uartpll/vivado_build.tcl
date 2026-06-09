set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv top.sv
read_xdc top.xdc
set defs ""
set tag "PLL"
if {[info exists ::env(PLLDEF)] && $::env(PLLDEF) ne ""} {
    set defs "-verilog_define $::env(PLLDEF)"
    set tag $::env(PLLDEF)
}
synth_design -top top -part $part {*}$defs
opt_design
place_design
route_design
report_timing_summary -file /tmp/uartpll_timing.rpt
puts "=== WNS ==="
puts [get_property SLACK [get_timing_paths -delay_type max]]
write_bitstream -force /tmp/uartpll_${tag}_vivado.bit
puts "WROTE /tmp/uartpll_${tag}_vivado.bit"
puts "uarttxonly_BUILD_DONE"
