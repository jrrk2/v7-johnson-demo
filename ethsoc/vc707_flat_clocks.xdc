# flat-netlist version of vc707_ethsoc_clocks.xdc: the SVS EDIF has no
# hierarchy, so match the gtxe2 cell by flat-name suffix
create_clock -period 16.000 -name gt_txoutclk \
    [get_pins -hierarchical -filter {NAME =~ *gtxe2_i/TXOUTCLK}]
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sysclk] \
    -group [get_clocks -include_generated_clocks gt_txoutclk] \
    -group [get_clocks -include_generated_clocks sgmii_refclk]
