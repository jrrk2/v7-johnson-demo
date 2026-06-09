# top_min on the Si570 USER_CLOCK (AK34/AL34) at 156.25 MHz (period 6.400 ns).
# Open-flow build: the full calc cannot close timing at the 200 MHz sysclk
# (Fmax ~153-185 MHz in nextpnr), so we use the slower user_clock.  Baud LFSR
# divider recomputed for 156.25 MHz (top_min.sv USE_USERCLK -> /85, 0x2D).
set_property PACKAGE_PIN AK34 [get_ports user_clock_p]
set_property PACKAGE_PIN AL34 [get_ports user_clock_n]
set_property IOSTANDARD LVDS [get_ports user_clock_p]
set_property IOSTANDARD LVDS [get_ports user_clock_n]
create_clock -period 6.400 -name userclk [get_ports user_clock_p]

# CPU_RESET button (active-high pressed).
set_property PACKAGE_PIN AV40 [get_ports rst]
set_property IOSTANDARD LVCMOS18 [get_ports rst]

# USB-UART, 115200 8N1.  tx: FPGA->host (AU36); rx: host->FPGA (AU33)
set_property PACKAGE_PIN AU36 [get_ports tx]
set_property PACKAGE_PIN AU33 [get_ports rx]
set_property IOSTANDARD LVCMOS18 [get_ports tx]
set_property IOSTANDARD LVCMOS18 [get_ports rx]

# 8 user LEDs (GPIO_LED_0..7_LS).
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
