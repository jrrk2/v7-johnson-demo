open_checkpoint vc707_arpm_impl.dcp
set site [get_sites SLICE_X220Y19]
puts "SITE: $site  used-site-pips:"
foreach sp [get_site_pips -quiet -of $site] {
    # only "used" ones carry a net
    set n [get_nets -quiet -of $sp]
    if {$n ne ""} { puts "  SITEPIP $sp   net=$n" }
}
puts "== nets matching xlnx_opt =="
foreach n [get_nets -hierarchical -quiet -filter {NAME =~ *xlnx_opt*}] { puts "  NET $n" }
puts "== all site pips of site (naming sample) =="
set i 0
foreach sp [get_site_pips -quiet -of $site] { puts "  ALLSP $sp"; incr i; if {$i>25} break }
puts "== BDI1MUX / DI-related bel pins =="
foreach bp [get_bel_pins -quiet -of $site -filter {NAME =~ *DI*}] { puts "  BP $bp" }
puts "DONE_PROBE"
