# 200 MHz LVDS sysclk (Si5324) on E19/E18, bank 38 HP.
set_property PACKAGE_PIN E19 [get_ports sysclk_p]
set_property PACKAGE_PIN E18 [get_ports sysclk_n]
set_property IOSTANDARD LVDS [get_ports sysclk_p]
set_property IOSTANDARD LVDS [get_ports sysclk_n]
create_clock -period 5.000 -name sysclk [get_ports sysclk_p]

# CPU_RESET button (active-high pressed).
set_property PACKAGE_PIN AV40 [get_ports rst]
set_property IOSTANDARD LVCMOS18 [get_ports rst]

# USB-UART (FT2232 channel -> /dev/ttyUSB*), 115200 8N1.
#   tx: FPGA -> host (AU36);  rx: host -> FPGA (AU33)
set_property PACKAGE_PIN AU36 [get_ports tx]
set_property PACKAGE_PIN AU33 [get_ports rx]
set_property IOSTANDARD LVCMOS18 [get_ports tx]
set_property IOSTANDARD LVCMOS18 [get_ports rx]

# 4 LEDs (GPIO_LED_0..3_LS), show the received-character count.
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
