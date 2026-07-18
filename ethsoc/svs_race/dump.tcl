proc dump_drivers {fname {prefix ""}} {
  set f [open $fname w]
  foreach cell [get_cells -hierarchical -filter "IS_PRIMITIVE"] {
    set cn [get_property NAME $cell]
    if {$prefix ne "" && [string first $prefix $cn] != 0} continue
    set ct [get_property REF_NAME $cell]
    foreach pin [get_pins -of $cell -filter "DIRECTION == IN"] {
      set net [get_nets -of $pin]
      if {$net eq ""} { puts $f "$ct|$cn|[get_property REF_PIN_NAME $pin]|UNCONN|"; continue }
      set drv [get_pins -leaf -of $net -filter "DIRECTION == OUT"]
      set dtxt ""
      foreach d $drv { append dtxt "[get_property PARENT_CELL $d].[get_property REF_PIN_NAME $d];" }
      set ports [get_ports -quiet -of $net -filter "DIRECTION == IN"]
      foreach p $ports { append dtxt "PORT:$p;" }
      set nt [get_property TYPE $net]
      puts $f "$ct|$cn|[get_property REF_PIN_NAME $pin]|$dtxt|$nt"
    }
  }
  close $f
}
# golden: link the flat netlist standalone (top = support wrapper w/ GT)
read_verilog /home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v
link_design -top gig_ethernet_pcs_pma_0 -part xc7vx485tffg1761-2
dump_drivers /tmp/eb/drvdump/gold.txt
puts "=== GOLD DUMPED ==="
close_design
# svs: link the emitted sgmii EDIF
read_edif /tmp/eb/hybrid3/sgmii_soc.edf
link_design -top sgmii_soc -part xc7vx485tffg1761-2
dump_drivers /tmp/eb/drvdump/svs.txt i_pcs_pma_258__inst__
puts "=== SVS DUMPED ==="
