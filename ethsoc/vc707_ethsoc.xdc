# 200 MHz LVDS sysclk (bank 38, HP)
set_property PACKAGE_PIN E19 [get_ports clk_p]
set_property PACKAGE_PIN E18 [get_ports clk_n]
set_property IOSTANDARD LVDS [get_ports clk_p]
set_property IOSTANDARD LVDS [get_ports clk_n]
create_clock -period 5.000 -name sysclk [get_ports clk_p]

# CPU_RESET pushbutton (active-high)
set_property PACKAGE_PIN AV40 [get_ports rst]
set_property IOSTANDARD LVCMOS18 [get_ports rst]
set_false_path -from [get_ports rst]

# USB-UART via CP2103 (bank 13, LVCMOS18)
set_property PACKAGE_PIN AU36 [get_ports uart_tx]
set_property PACKAGE_PIN AU33 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS18 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS18 [get_ports uart_rx]

# LEDs LD0..LD7
set_property PACKAGE_PIN AM39 [get_ports {led[0]}]
set_property PACKAGE_PIN AN39 [get_ports {led[1]}]
set_property PACKAGE_PIN AR37 [get_ports {led[2]}]
set_property PACKAGE_PIN AT37 [get_ports {led[3]}]
set_property PACKAGE_PIN AR35 [get_ports {led[4]}]
set_property PACKAGE_PIN AP41 [get_ports {led[5]}]
set_property PACKAGE_PIN AP42 [get_ports {led[6]}]
set_property PACKAGE_PIN AU39 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[*]}]

# SGMII Ethernet (Marvell 88E1111 PHY)
# 125 MHz SGMII refclk from the PHY to MGTREFCLK0 of GTX bank 117
set_property PACKAGE_PIN AH8 [get_ports sgmii_refclk_p]
set_property PACKAGE_PIN AH7 [get_ports sgmii_refclk_n]
create_clock -period 8.000 -name sgmii_refclk [get_ports sgmii_refclk_p]

# SGMII serial data (GTX bank 117)
set_property PACKAGE_PIN AN2 [get_ports sgmii_txp]
set_property PACKAGE_PIN AN1 [get_ports sgmii_txn]
set_property PACKAGE_PIN AM8 [get_ports sgmii_rxp]
set_property PACKAGE_PIN AM7 [get_ports sgmii_rxn]

# PHY reset + MDIO (bank 13/14 LVCMOS18)
set_property -dict {PACKAGE_PIN AJ33 IOSTANDARD LVCMOS18} [get_ports eth_rst_n]
set_false_path -to [get_ports eth_rst_n]
set_property -dict {PACKAGE_PIN AH33 IOSTANDARD LVCMOS18} [get_ports eth_mdc]
set_property -dict {PACKAGE_PIN AK33 IOSTANDARD LVCMOS18} [get_ports eth_mdio]
set_false_path -to [get_ports eth_mdc]
set_false_path -to [get_ports eth_mdio]
set_false_path -from [get_ports eth_mdio]

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
