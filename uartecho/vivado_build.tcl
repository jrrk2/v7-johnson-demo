# Golden Vivado build of the UART echo demo (full synth -> place -> route ->
# bitstream).  Reference bitstream while the open flow is brought up.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv top.sv uart_echo.sv
read_xdc top.xdc
synth_design -top top -part $part
opt_design
place_design
route_design
report_timing_summary -file /tmp/uartecho_timing.rpt
puts "=== WNS (setup) ==="
puts [get_property SLACK [get_timing_paths -delay_type max]]
write_bitstream -force /tmp/uartecho_vivado.bit
puts "UARTECHO_BUILD_DONE"
