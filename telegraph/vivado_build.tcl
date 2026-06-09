# Build the open-flow telegraph design (200 MHz SYSCLK) through Vivado as a
# reference: if this bitstream transmits but the open-flow one doesn't, the
# design is sound and the open flow is the culprit.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog top.v telegraph_core.v
read_xdc top.xdc
synth_design -top top -part $part
opt_design
place_design
route_design
report_timing_summary -file /tmp/tg_vivado_timing.rpt
puts "=== WNS (setup) ==="
puts [get_property SLACK [get_timing_paths -delay_type max]]
write_bitstream -force /tmp/telegraph_vivado.bit
