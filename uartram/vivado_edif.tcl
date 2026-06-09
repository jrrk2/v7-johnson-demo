set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv calc_core.sv byte_fifo.sv top.sv
synth_design -top top -part $part -flatten_hierarchy full
puts "RAMB18: [llength [get_cells -hier -filter {REF_NAME =~ RAMB18*}]]  RAMB36: [llength [get_cells -hier -filter {REF_NAME =~ RAMB36*}]]"
write_edif -force /tmp/uartram_synth.edif
puts "UARTRAM_EDIF_DONE"
