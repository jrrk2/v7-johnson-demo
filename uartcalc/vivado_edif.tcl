set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog [glob uart_src/*.sv]
read_verilog mult_seq.v bin2dec.v rpn_calc.v
read_verilog -sv top.sv
synth_design -top top -part $part -flatten_hierarchy full
write_edif -force /tmp/uartcalc_synth.edif
puts "UARTCALC_EDIF_DONE"
