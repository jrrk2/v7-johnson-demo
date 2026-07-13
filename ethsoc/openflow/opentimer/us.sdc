create_clock -period 20.0 -name mmcm_clkout0 [get_ports mmcm_clkout0]
set_input_transition 0.020 -min -rise [get_ports const0;]
set_input_transition 0.020 -min -fall [get_ports const0;]
set_input_transition 0.020 -max -rise [get_ports const0;]
set_input_transition 0.020 -max -fall [get_ports const0;]
set_input_delay 0.0 -max [get_ports const0;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports const1;]
set_input_transition 0.020 -min -fall [get_ports const1;]
set_input_transition 0.020 -max -rise [get_ports const1;]
set_input_transition 0.020 -max -fall [get_ports const1;]
set_input_delay 0.0 -max [get_ports const1;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports led_OBUF_6;]
set_input_transition 0.020 -min -fall [get_ports led_OBUF_6;]
set_input_transition 0.020 -max -rise [get_ports led_OBUF_6;]
set_input_transition 0.020 -max -fall [get_ports led_OBUF_6;]
set_input_delay 0.0 -max [get_ports led_OBUF_6;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports led_OBUF_7;]
set_input_transition 0.020 -min -fall [get_ports led_OBUF_7;]
set_input_transition 0.020 -max -rise [get_ports led_OBUF_7;]
set_input_transition 0.020 -max -fall [get_ports led_OBUF_7;]
set_input_delay 0.0 -max [get_ports led_OBUF_7;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports mmcm_clkout0;]
set_input_transition 0.020 -min -fall [get_ports mmcm_clkout0;]
set_input_transition 0.020 -max -rise [get_ports mmcm_clkout0;]
set_input_transition 0.020 -max -fall [get_ports mmcm_clkout0;]
set_input_delay 0.0 -max [get_ports mmcm_clkout0;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports rst;]
set_input_transition 0.020 -min -fall [get_ports rst;]
set_input_transition 0.020 -max -rise [get_ports rst;]
set_input_transition 0.020 -max -fall [get_ports rst;]
set_input_delay 0.0 -max [get_ports rst;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports rst_sync;]
set_input_transition 0.020 -min -fall [get_ports rst_sync;]
set_input_transition 0.020 -max -rise [get_ports rst_sync;]
set_input_transition 0.020 -max -fall [get_ports rst_sync;]
set_input_delay 0.0 -max [get_ports rst_sync;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports stb;]
set_input_transition 0.020 -min -fall [get_ports stb;]
set_input_transition 0.020 -max -rise [get_ports stb;]
set_input_transition 0.020 -max -fall [get_ports stb;]
set_input_delay 0.0 -max [get_ports stb;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports sysclk_ibuf;]
set_input_transition 0.020 -min -fall [get_ports sysclk_ibuf;]
set_input_transition 0.020 -max -rise [get_ports sysclk_ibuf;]
set_input_transition 0.020 -max -fall [get_ports sysclk_ibuf;]
set_input_delay 0.0 -max [get_ports sysclk_ibuf;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports txb;]
set_input_transition 0.020 -min -fall [get_ports txb;]
set_input_transition 0.020 -max -rise [get_ports txb;]
set_input_transition 0.020 -max -fall [get_ports txb;]
set_input_delay 0.0 -max [get_ports txb;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports u_tx_n_2;]
set_input_transition 0.020 -min -fall [get_ports u_tx_n_2;]
set_input_transition 0.020 -max -rise [get_ports u_tx_n_2;]
set_input_transition 0.020 -max -fall [get_ports u_tx_n_2;]
set_input_delay 0.0 -max [get_ports u_tx_n_2;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports uart_rx;]
set_input_transition 0.020 -min -fall [get_ports uart_rx;]
set_input_transition 0.020 -max -rise [get_ports uart_rx;]
set_input_transition 0.020 -max -fall [get_ports uart_rx;]
set_input_delay 0.0 -max [get_ports uart_rx;] -clock mmcm_clkout0
set_input_transition 0.020 -min -rise [get_ports uart_tx_OBUF;]
set_input_transition 0.020 -min -fall [get_ports uart_tx_OBUF;]
set_input_transition 0.020 -max -rise [get_ports uart_tx_OBUF;]
set_input_transition 0.020 -max -fall [get_ports uart_tx_OBUF;]
set_input_delay 0.0 -max [get_ports uart_tx_OBUF;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports led_0;]
set_output_delay 0.0 -max [get_ports led_0;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports led_1;]
set_output_delay 0.0 -max [get_ports led_1;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports led_2;]
set_output_delay 0.0 -max [get_ports led_2;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports led_3;]
set_output_delay 0.0 -max [get_ports led_3;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports led_4;]
set_output_delay 0.0 -max [get_ports led_4;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports led_5;]
set_output_delay 0.0 -max [get_ports led_5;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports led_6;]
set_output_delay 0.0 -max [get_ports led_6;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports led_7;]
set_output_delay 0.0 -max [get_ports led_7;] -clock mmcm_clkout0
set_load -pin_load 0.004 [get_ports uart_tx;]
set_output_delay 0.0 -max [get_ports uart_tx;] -clock mmcm_clkout0
