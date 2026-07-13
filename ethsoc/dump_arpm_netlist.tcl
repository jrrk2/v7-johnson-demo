open_checkpoint vc707_arpm_impl.dcp
write_verilog -force -mode design -cell [get_cells eth/eth_macro1] eth_macro_gold_raw.v
puts "GOLD NETLIST DONE"
