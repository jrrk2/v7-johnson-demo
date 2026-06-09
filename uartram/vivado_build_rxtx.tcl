set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv top_rxtx.sv
read_xdc top.xdc
synth_design -top top -part $part
opt_design
place_design
route_design
write_bitstream -force /home/jonathan/json_drc-portable/work/rxtx_vivado.bit
puts "RXTX_VIVADO_DONE"
