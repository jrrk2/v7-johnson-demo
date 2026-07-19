set D [expr {[info exists ::env(ETH)] ? $::env(ETH) : "/home/jonathan/v7-johnson-demo/ethsoc"}]
set H [expr {[info exists ::env(W)] ? $::env(W) : "/tmp/svs_diag"}]
# ---------- build 1: all-golden diagnostic ----------
read_verilog -sv [list $D/sgmii_soc.sv $D/eth_mac_1g.sv $D/axis_gmii_rx.sv $D/axis_gmii_tx.sv $D/rgmii_lfsr.sv]
read_verilog [list $D/pcs_pma_flat.v $D/vc707_sgmii_diag.v]
synth_design -top top -part xc7vx485tffg1761-2 -flatten_hierarchy full -verilog_define VC707
read_xdc $D/vc707_ethsoc.xdc
read_xdc $D/vc707_ethsoc_clocks.xdc
read_xdc $D/vc707_diag_sw.xdc
opt_design
place_design
route_design
puts [report_route_status -return_string]
write_bitstream -force $H/diag_gold.bit
puts "=== DIAG_GOLD_DONE ==="
close_design
# ---------- build 2: diag top + SVS sgmii_soc EDIF ----------
read_verilog [list $D/vc707_sgmii_diag.v]
read_verilog [file join [file dirname [info script]] sgmii_soc_bb.v]
synth_design -top top -part xc7vx485tffg1761-2 -flatten_hierarchy full -verilog_define VC707
write_edif -force $H/diag_top.edf
close_design
read_edif $H/diag_top.edf
read_edif [expr {[info exists ::env(SGMII_EDIF)] ? $::env(SGMII_EDIF) : "/tmp/svs_hybrid_sgmii/sgmii_soc.edf"}]
link_design -top top -part xc7vx485tffg1761-2
read_xdc $D/vc707_ethsoc.xdc
read_xdc $D/vc707_ethsoc_clocks.xdc
read_xdc $D/vc707_diag_sw.xdc
opt_design
place_design
route_design
puts [report_route_status -return_string]
write_bitstream -force $H/diag_svs.bit
puts "=== DIAG_SVS_DONE ==="
