# In-context implementation of eth_macro via eth_macro_harness (real bonded
# pins for refclk/SGMII, so IBUFDS_GTE2/GTX place legally — the OOC flow
# rejects them as "not bonded").  GT/clocking cells are LOC-anchored to the
# golden ethloop sites; all other macro fabric is confined to a reserved
# pblock around the GT/MMCM clock regions with contained routing, so the
# extracted macro can never collide with user logic in the merge flow.
# Output: eth_macro_harness.dcp (macro cells under u_macro/).
set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog -sv [list eth_macro.sv sgmii_soc.sv eth_mac_1g.sv \
    axis_gmii_rx.sv axis_gmii_tx.sv rgmii_lfsr.sv]
read_verilog [list async_fifo.v eth_stream_conv.v eth_macro_harness.v]
read_verilog pcs_pma_flat.v
synth_design -top eth_macro_harness -part $part \
    -flatten_hierarchy rebuilt -verilog_define VC707

# ---- pins (same as vc707_ethsoc.xdc) --------------------------------------
set_property PACKAGE_PIN E19 [get_ports clk_p]
set_property PACKAGE_PIN E18 [get_ports clk_n]
set_property IOSTANDARD LVDS [get_ports clk_p]
set_property IOSTANDARD LVDS [get_ports clk_n]
set_property PACKAGE_PIN AV40 [get_ports rst]
set_property IOSTANDARD LVCMOS18 [get_ports rst]
set_property PACKAGE_PIN AH8 [get_ports sgmii_refclk_p]
set_property PACKAGE_PIN AH7 [get_ports sgmii_refclk_n]
set_property PACKAGE_PIN AN2 [get_ports sgmii_txp]
set_property PACKAGE_PIN AN1 [get_ports sgmii_txn]
set_property PACKAGE_PIN AM8 [get_ports sgmii_rxp]
set_property PACKAGE_PIN AM7 [get_ports sgmii_rxn]
set_property PACKAGE_PIN AM39 [get_ports {led[0]}]
set_property PACKAGE_PIN AN39 [get_ports {led[1]}]
set_property PACKAGE_PIN AR37 [get_ports {led[2]}]
set_property PACKAGE_PIN AT37 [get_ports {led[3]}]
set_property PACKAGE_PIN AR35 [get_ports {led[4]}]
set_property PACKAGE_PIN AP41 [get_ports {led[5]}]
set_property PACKAGE_PIN AP42 [get_ports {led[6]}]
set_property PACKAGE_PIN AU39 [get_ports {led[7]}]
foreach l [get_ports led*] { set_property IOSTANDARD LVCMOS18 $l }

# ---- clocks ----------------------------------------------------------------
create_clock -period 5.000 -name sysclk [get_ports clk_p]
create_clock -period 8.000 -name sgmii_refclk [get_ports sgmii_refclk_p]
create_clock -period 16.000 -name gt_txoutclk \
    [get_pins -hierarchical -filter {NAME =~ */gtxe2_i/TXOUTCLK}]
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sysclk] \
    -group [get_clocks -include_generated_clocks gt_txoutclk] \
    -group [get_clocks -include_generated_clocks sgmii_refclk]

# ---- GT/clocking anchors (golden ethloop sites) ----------------------------
set pcs u_macro/sgmii_soc1/i_pcs_pma/inst
set_property LOC IBUFDS_GTE2_X1Y0   [get_cells $pcs/core_clocking_i/ibufds_gtrefclk]
# MMCM re-anchored into the GT's clock region (golden had X0Y3, far left;
# GT config is FASM-driven now, so only geometry-quality matters here)
set_property LOC MMCME2_ADV_X1Y0    [get_cells $pcs/core_clocking_i/mmcm_adv_inst]
set_property LOC BUFGCTRL_X0Y0      [get_cells $pcs/core_clocking_i/rxrecclkbufg]
set_property LOC BUFGCTRL_X0Y1      [get_cells $pcs/core_clocking_i/bufg_userclk]
set_property LOC BUFGCTRL_X0Y2      [get_cells $pcs/core_clocking_i/bufg_gtrefclk]
set_property LOC BUFGCTRL_X0Y3      [get_cells $pcs/core_clocking_i/bufg_userclk2]
set_property LOC BUFGCTRL_X0Y4      [get_cells $pcs/core_clocking_i/bufg_txoutclk]
set_property LOC GTXE2_COMMON_X1Y0  [get_cells $pcs/core_gt_common_i/gtxe2_common_i]
set_property LOC GTXE2_CHANNEL_X1Y1 [get_cells $pcs/pcs_pma_block_i/transceiver_inst/gtwizard_inst/inst/gtwizard_i/gt0_GTWIZARD_i/gtxe2_i]

# ---- reserved macro pblock --------------------------------------------------
# single reserved clock region: the GT channel's (MMCM re-anchored into it)
set gt_region [get_clock_regions -of_objects [get_sites GTXE2_CHANNEL_X1Y1]]
puts "MACRO PBLOCK REGION: $gt_region"
create_pblock pb_macro
resize_pblock pb_macro -add "CLOCKREGION_${gt_region}" 
add_cells_to_pblock pb_macro [get_cells u_macro]
# the LOC-anchored BUFGs live in the center clock column, outside the pblock
remove_cells_from_pblock pb_macro [get_cells [list \
    $pcs/core_clocking_i/rxrecclkbufg \
    $pcs/core_clocking_i/bufg_userclk \
    $pcs/core_clocking_i/bufg_gtrefclk \
    $pcs/core_clocking_i/bufg_userclk2 \
    $pcs/core_clocking_i/bufg_txoutclk]]
# keep user logic out and macro routing inside: the region is the macro's
set_property EXCLUDE_PLACEMENT 1 [get_pblocks pb_macro]
set_property CONTAIN_ROUTING  1 [get_pblocks pb_macro]

place_design
route_design
report_timing_summary -file eth_macro_harness_timing.rpt
write_checkpoint -force eth_macro_harness.dcp
puts "ETH_MACRO_HARNESS_DONE"
