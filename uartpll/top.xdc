# 200 MHz LVDS sysclk (Si5324) on E19/E18, bank 38 HP.
set_property PACKAGE_PIN E19 [get_ports sysclk_p]
set_property PACKAGE_PIN E18 [get_ports sysclk_n]
set_property IOSTANDARD LVDS [get_ports sysclk_p]
set_property IOSTANDARD LVDS [get_ports sysclk_n]
create_clock -period 5.000 -name sysclk [get_ports sysclk_p]

# Si570 USER_CLOCK (AK34/AL34), reprogrammed to 125 MHz.  Active when built
# with -verilog_define USE_USERCLK; otherwise this port is unused.
set_property PACKAGE_PIN AK34 [get_ports user_clock_p]
set_property PACKAGE_PIN AL34 [get_ports user_clock_n]
set_property IOSTANDARD LVDS [get_ports user_clock_p]
set_property IOSTANDARD LVDS [get_ports user_clock_n]
create_clock -period 6.400 -name userclk [get_ports user_clock_p]

# SGMII 125 MHz reference clock = MGTREFCLK0_113 (AH8/AH7).  Dedicated GT refclk
# pins: PACKAGE_PIN only, no IOSTANDARD.  Active when built with -verilog_define
# USE_SGMII (brought in via IBUFDS_GTE2, ODIV2 = 62.5 MHz to fabric).
set_property PACKAGE_PIN AH8 [get_ports sgmii_clk_p]
set_property PACKAGE_PIN AH7 [get_ports sgmii_clk_n]
create_clock -period 8.000 -name sgmiiclk [get_ports sgmii_clk_p]

# CPU_RESET button (active-high pressed).
set_property PACKAGE_PIN AV40 [get_ports rst]
set_property IOSTANDARD LVCMOS18 [get_ports rst]

# USB-UART TX only (FPGA -> host, AU36), 115200 8N1.
set_property PACKAGE_PIN AU36 [get_ports tx]
set_property IOSTANDARD LVCMOS18 [get_ports tx]

# 8 user LEDs (GPIO_LED_0..7_LS) = the current transmit byte.
set_property PACKAGE_PIN AM39 [get_ports {led[0]}]
set_property PACKAGE_PIN AN39 [get_ports {led[1]}]
set_property PACKAGE_PIN AR37 [get_ports {led[2]}]
set_property PACKAGE_PIN AT37 [get_ports {led[3]}]
set_property PACKAGE_PIN AR35 [get_ports {led[4]}]
set_property PACKAGE_PIN AP41 [get_ports {led[5]}]
set_property PACKAGE_PIN AP42 [get_ports {led[6]}]
set_property PACKAGE_PIN AU39 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[7]}]

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
