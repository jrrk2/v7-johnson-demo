set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog top.v telegraph_core.v
synth_design -top top -part $part
write_edif -force /tmp/telegraph_synth.edif
