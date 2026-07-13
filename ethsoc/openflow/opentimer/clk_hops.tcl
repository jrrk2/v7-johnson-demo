open_checkpoint ethsoc/vc707_ethloop.dcp
# the userclk2/eth_clk global clock net driven by bufg_userclk2
set net [get_nets eth/RAMB16_inst_tx/clka]
puts "NET: $net  fanout=[llength [get_pins -leaf -of $net -filter {DIRECTION==IN}]]  pips=[llength [get_pips -of $net]]"
# pip type histogram over the whole net
array set H {}
foreach p [get_pips -of $net] {
  set t [get_property TILE $p]
  set tt [get_property TYPE [get_tiles $t]]
  incr H($tt)
}
puts "PIP-TILE-TYPE HISTOGRAM (whole net):"
foreach {k v} [array get H] { puts "  $k : $v" }
# now the path to ONE sink: use a routed node walk approximation via get_pips between driver and one load
set drv [get_pins -leaf -of $net -filter {DIRECTION==OUT}]
set snk [lindex [get_pins -leaf -of $net -filter {DIRECTION==IN}] 0]
puts "DRV=$drv  SNK=$snk"
puts "CLK_HOPS_DONE"
