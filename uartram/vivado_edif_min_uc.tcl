set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv calc_core.sv byte_fifo.sv lfsr_div.sv uart_rx_lfsr.sv top_min.sv
synth_design -top top -part $part -flatten_hierarchy full -verilog_define USE_USERCLK
puts "INSTS: [llength [get_cells -hier]]  DSP48: [llength [get_cells -hier -filter {REF_NAME =~ DSP48*}]]  RAMB18: [llength [get_cells -hier -filter {REF_NAME =~ RAMB18*}]]"
write_edif -force /tmp/uartram_synth.edif
puts "MIN_EDIF_DONE"
