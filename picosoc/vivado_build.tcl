# Vivado golden build of PicoSoC: synth + place + route + bitstream, as the
# reference to compare against the open-flow (yosys+nextpnr) FASM.  Per-frame
# CRC is required so prjxray's bitread/bit2fasm can recover the FASM.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv vc707_picosoc.v picosoc_noflash.v picorv32.v simpleuart.v spimemio.v progmem.v
read_xdc vc707_picosoc.xdc
synth_design -top top -part $part
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.PERFRAMECRC YES [current_design]
opt_design
place_design
route_design
report_timing_summary -file /tmp/picosoc_vivado_timing.rpt
puts "=== WNS (setup) ==="
puts [get_property SLACK [get_timing_paths -delay_type max]]
write_checkpoint -force /tmp/picosoc_vivado.dcp
write_bitstream -force /tmp/picosoc_vivado.bit
puts "PICOSOC_VIVADO_DONE"
