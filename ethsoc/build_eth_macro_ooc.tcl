# Out-of-context implementation of eth_macro: the frozen 125 MHz Ethernet
# island (PCS/PMA + GTX + MAC + byte/word converters + eth-side async-FIFO
# halves).  Implemented once by Vivado (hold-clean), then imported into the
# nextpnr flow as a placed+routed macro.
#
# Placement is anchored to the golden flat ethloop build via
# eth_macro_locs.xdc (extract_eth_macro_locs.tcl) so the GT channel, refclk
# IBUFDS_GTE2, BUFGs and MMCM sit exactly where the (validated, splice-free)
# GT frame config expects them.  Routing is redone by Vivado with full
# setup+hold analysis.
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [list eth_macro.sv sgmii_soc.sv eth_mac_1g.sv \
    axis_gmii_rx.sv axis_gmii_tx.sv rgmii_lfsr.sv]
read_verilog [list async_fifo.v eth_stream_conv.v]
read_verilog pcs_pma_flat.v
synth_design -mode out_of_context -top eth_macro -part $part \
    -flatten_hierarchy rebuilt -verilog_define VC707

# ---- clocks --------------------------------------------------------------
# free-running PCS/PMA independent clock = cpu_clk (50 MHz) in vc707 tops
create_clock -period 20.000 -name clk_int [get_ports clk_int]
# GT reference clock enters through the sgmii_refclk_p port (IBUFDS_GTE2)
create_clock -period 8.000 -name sgmii_refclk [get_ports sgmii_refclk_p]
# GT TXOUTCLK = 62.5 MHz for 1G SGMII; userclk2 (125 MHz) derived via MMCM
create_clock -period 16.000 -name gt_txoutclk \
    [get_pins -hierarchical -filter {NAME =~ */gtxe2_i/TXOUTCLK}]
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk_int] \
    -group [get_clocks -include_generated_clocks gt_txoutclk] \
    -group [get_clocks -include_generated_clocks sgmii_refclk]

# ---- macro-boundary ports are async by construction ----------------------
# Gray pointers land in 2-flop synchronisers; the distributed-RAM read ports
# are consumed only when stable (async-FIFO occupancy argument).
set_false_path -from [get_ports {rx_rd_gray[*] rx_rd_addr[*] tx_wr_gray[*] tx_rd_data[*] rst_int}]
set_false_path -to   [get_ports {rx_wr_gray[*] rx_rd_data[*] tx_rd_gray[*] tx_rd_addr[*]}]

# ---- golden placement anchors --------------------------------------------
read_xdc eth_macro_locs.xdc

place_design
route_design
report_timing_summary -file eth_macro_ooc_timing.rpt
write_checkpoint -force eth_macro.dcp
puts "eth_macro OOC build complete: eth_macro.dcp"
