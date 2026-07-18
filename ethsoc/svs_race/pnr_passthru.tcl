read_edif /tmp/arp_edif_dir/top.edf
link_design -part xc7vx485tffg1761-2 -top top
read_xdc /home/jonathan/v7-johnson-demo/ethsoc/r0_pins.xdc
read_xdc /tmp/eb/passthru_clocks.xdc
puts "=== OPT ==="; opt_design
puts "=== PLACE ==="; place_design
puts "=== ROUTE ==="; route_design
puts [report_route_status -return_string]
write_bitstream -force /tmp/eb/arp_passthru.bit
puts "=== PASSTHRU_DONE ==="
