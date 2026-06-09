set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv top.sv
read_xdc top.xdc
synth_design -top top -part $part
opt_design
place_design
route_design
report_timing_summary -file /tmp/uarttxprbs_timing.rpt
puts "=== WNS ==="
puts [get_property SLACK [get_timing_paths -delay_type max]]
write_bitstream -force /tmp/uarttxprbs_vivado.bit
puts "uarttxprbs_BUILD_DONE"
