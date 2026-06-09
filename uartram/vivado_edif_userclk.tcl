set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv calc_core.sv byte_fifo.sv top.sv
synth_design -top top -part $part -flatten_hierarchy full -verilog_define USE_USERCLK -verilog_define BAUDDIV=85
puts "RAMB18: [llength [get_cells -hier -filter {REF_NAME =~ RAMB18*}]]  DSP48: [llength [get_cells -hier -filter {REF_NAME =~ DSP48*}]]  CARRY4: [llength [get_cells -hier -filter {REF_NAME =~ CARRY4*}]]"
write_edif -force /tmp/uartram_synth.edif
puts "UARTRAM_EDIF_DONE"
