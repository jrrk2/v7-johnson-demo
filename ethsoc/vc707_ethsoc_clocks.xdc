# Clock constraints for the netlist (no-IP) flow: replaces the IP's
# internal OOC XDC.  Vivado-only syntax (get_pins -hier); nextpnr gets its
# clocks from --freq and the main XDC.
#
# GT TXOUTCLK = 62.5 MHz for 1G SGMII; userclk2 (125 MHz) is then
# auto-derived through the MMCM.
create_clock -period 16.000 -name gt_txoutclk \
    [get_pins -hierarchical -filter {NAME =~ */gtxe2_i/TXOUTCLK}]

# cpu_clk (50 MHz) comes from the top-level MMCME2_ADV and is auto-derived
# by Vivado from sysclk; no manual generated clocks needed.

# The MAC/framing CDC uses dual-clock BRAMs and synchronizers; the only
# true synchronous relationships are within each domain.
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sysclk] \
    -group [get_clocks -include_generated_clocks gt_txoutclk] \
    -group [get_clocks -include_generated_clocks sgmii_refclk]
