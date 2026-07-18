# Vivado P&R of the SVS-synthesized pass-through EDIF (open synthesis, Vivado P&R).
set part xc7vx485tffg1761-2
set E /home/jonathan/v7-johnson-demo/ethsoc
read_edif /tmp/eb/vivado_pnr/top.edf
link_design -top top -part $part
read_xdc $E/vc707_ethsoc.xdc
read_xdc $E/vc707_ethsoc_clocks.xdc
puts "=== LINKED ==="
opt_design
puts "=== OPT DONE ==="
place_design
puts "=== PLACE DONE ==="
route_design
puts "=== ROUTE DONE ==="
puts [report_route_status -return_string]
report_timing_summary -file /tmp/eb/vivado_pnr/timing.rpt -max_paths 3
write_checkpoint -force /tmp/eb/vivado_pnr/passthru.dcp
write_bitstream -force /tmp/eb/vivado_pnr/passthru.bit
puts "=== PASSTHRU_PNR_DONE ==="
