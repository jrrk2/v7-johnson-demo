set D /home/jonathan/v7-johnson-demo/ethsoc
foreach f {arp_ctrl framing_top_sgmii sgmii_soc eth_mac_1g axis_gmii_rx axis_gmii_tx \
           rgmii_lfsr dualmem_widen dualmem_widen8 eth_macro dualmem64} {
  read_verilog -sv $D/$f.sv
}
foreach f {async_fifo ramb16_compat eth_stream_conv pcs_pma_flat vc707_arp} {
  read_verilog $D/$f.v
}
read_xdc $D/r0_pins.xdc
synth_design -top top -part xc7vx485tffg1761-2 -flatten_hierarchy full
write_edif -force /tmp/golden_samesrc.edf
puts "=== SYNTH DONE ==="
opt_design
place_design
route_design
puts [report_route_status -return_string]
write_bitstream -force /tmp/golden_samesrc.bit
puts "=== GOLDEN_SAMESRC_DONE ==="
