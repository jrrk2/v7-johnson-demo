set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [glob uart_src/*.sv]
read_verilog -sv top.sv
synth_design -top top -part $part -flatten_hierarchy full
write_edif -force /tmp/uarttxprbs_synth.edif
puts "uarttxprbs_EDIF_DONE"
