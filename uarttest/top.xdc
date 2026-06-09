# SYSCLK_P/N at E19/E18 — Bank 38 HP, real LVDS differential pair from
# the on-board Si5324 (200 MHz).  Period 5 ns.  Same clock as johnson.
set_property PACKAGE_PIN E19 [get_ports sysclk_p]
set_property PACKAGE_PIN E18 [get_ports sysclk_n]
set_property IOSTANDARD LVDS [get_ports sysclk_p]
set_property IOSTANDARD LVDS [get_ports sysclk_n]
create_clock -period 5.000 -name sysclk [get_ports sysclk_p]

# CPU_RESET button on VC707 — active-high when pressed.
set_property PACKAGE_PIN AV40 [get_ports rst]
set_property IOSTANDARD LVCMOS18 [get_ports rst]

# USB-UART: FPGA -> host TX on AU36 (FT2232 bridge -> /dev/ttyUSB*).
# Read it at 115200 8N1 to see the walking 'A'..'Z' telegraph.
set_property PACKAGE_PIN AU36 [get_ports ser_tx]
set_property IOSTANDARD LVCMOS18 [get_ports ser_tx]

# 4 LEDs (GPIO_LED_0..3_LS on VC707, all LVCMOS18)
set_property PACKAGE_PIN AM39 [get_ports {led[0]}]
set_property PACKAGE_PIN AN39 [get_ports {led[1]}]
set_property PACKAGE_PIN AR37 [get_ports {led[2]}]
set_property PACKAGE_PIN AT37 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {led[3]}]

set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
