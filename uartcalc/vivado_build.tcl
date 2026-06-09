set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog [glob uart_src/*.sv]
read_verilog mult_seq.v bin2dec.v rpn_calc.v
read_verilog -sv top.sv
read_xdc top.xdc
synth_design -top top -part $part
puts "BRAM: [llength [get_cells -hier -filter {REF_NAME =~ RAMB*}]]  DSP: [llength [get_cells -hier -filter {REF_NAME =~ DSP*}]]  LUTRAM: [llength [get_cells -hier -filter {REF_NAME =~ RAM*X* || REF_NAME =~ SRL*}]]"
opt_design
place_design
route_design
report_timing_summary -file /tmp/uartcalc_timing.rpt
puts "=== WNS ==="; puts [get_property SLACK [get_timing_paths -delay_type max]]
write_bitstream -force /tmp/uartcalc_vivado.bit
puts "UARTCALC_BUILD_DONE"
