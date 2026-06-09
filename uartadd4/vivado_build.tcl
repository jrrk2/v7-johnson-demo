set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv lfsr_div.sv uart_rx_lfsr.sv top.sv
read_xdc top.xdc
synth_design -top top -part $part
opt_design
place_design
route_design
report_timing_summary -file /tmp/uartadd4_timing.rpt
puts "=== WNS ==="
puts [get_property SLACK [get_timing_paths -delay_type max]]
puts "CARRY4 count: [llength [get_cells -hier -filter {REF_NAME =~ CARRY4*}]]"
write_bitstream -force /tmp/uartadd4_vivado.bit
puts "uartadd4_BUILD_DONE"
