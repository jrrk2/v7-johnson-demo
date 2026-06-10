create_project -force ip_proj /tmp/ethsoc_ip_proj -part xc7vx485tffg1761-2
set_property target_language Verilog [current_project]
import_ip /home/jonathan/v7-johnson-demo/ethsoc/ip/gig_ethernet_pcs_pma_0.xci -name gig_ethernet_pcs_pma_0
upgrade_ip [get_ips] -quiet
generate_target all [get_ips gig_ethernet_pcs_pma_0]
synth_ip [get_ips gig_ethernet_pcs_pma_0]
puts "IP_XCI: [get_property IP_FILE [get_ips gig_ethernet_pcs_pma_0]]"
puts "IP_REGEN_DONE"
