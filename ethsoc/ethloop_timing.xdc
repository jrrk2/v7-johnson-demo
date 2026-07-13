# Real per-domain clock constraints for the open flow (nextpnr xdc supports
# create_clock on internal nets).  The 125 MHz userclk2 domain is constrained
# at 4 ns: the TX BRAM port A runs on ~userclk2 (IS_CLKARDCLK_INVERTED), a
# HALF-CYCLE path nextpnr's single-edge model can't see -- a 4 ns envelope
# makes every userclk2 path meet both the 8 ns full-cycle and 4 ns half-cycle
# budgets.  (nextpnr treated these domains as unconstrained-at---freq before:
# everything was routed to a 20 ns target.)
create_clock -period 4.000 [get_nets eth.RAMB16_inst_rx.eth_clk]
create_clock -period 8.000 [get_nets eth.sgmii_soc1.i_pcs_pma.inst.core_clocking_i/rxrecclkbufg_n_0]
create_clock -period 16.000 [get_nets eth.sgmii_soc1.i_pcs_pma.inst.core_clocking_i/bufg_userclk_n_0]
create_clock -period 8.000 [get_nets eth.sgmii_soc1.i_pcs_pma.inst.core_clocking_i/bufg_gtrefclk_n_0]
create_clock -period 16.000 [get_nets eth.sgmii_soc1.i_pcs_pma.inst.core_clocking_i/txoutclk_bufg]
create_clock -period 20.000 [get_nets cpu_clk]
