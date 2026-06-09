set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv top_rxtx.sv
synth_design -top top -part $part -flatten_hierarchy full
write_edif -force /tmp/uartram_synth.edif
puts "RXTX_EDIF_DONE"
