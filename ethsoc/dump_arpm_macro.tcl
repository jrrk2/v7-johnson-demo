# Extract eth_macro from the WORKING golden vc707_arpm.dcp (arping 10/10).
# Locks EVERY pip whose tile lies in the macro's footprint -- including the
# macro-side fanout of boundary/user nets (e.g. rst_sync -> macro FFs) -- so
# the open flow's router only has to connect each such net's SOURCE to the
# macro edge, not thread it through the densely-locked interior.
set part xc7vx485tffg1761-2
open_checkpoint vc707_arpm_impl.dcp
# Freeze the WHOLE eth block (macro + framing): placement AND routing.  Since
# framing is now frozen-placed at its golden positions next to the macro, we can
# also lock its golden routing -- including the FIFO-boundary CDC nets that cross
# framing<->macro (tx_wr_gray, rx_rd_data, ...).  A net is locked iff EVERY one
# of its leaf pins lies under eth/ (fully internal to the frozen block).  Boundary
# nets to fresh arp_ctrl (lsu_addr, framing_rdata, i_arp_n_*) have pins outside
# eth/ and are deliberately left for router2 -- their arp_ctrl end is fresh.
set prefix {eth/}
set plen [string length $prefix]
set place_prefix {eth/}

# ---- 1. eth tile footprint: tiles of placed eth cells + tiles the
#         eth-internal routing traverses ----------------------------------
array set MT {}
foreach c [get_cells -hierarchical -filter "IS_PRIMITIVE && NAME =~ ${prefix}*"] {
    set loc [get_property LOC $c]
    if {$loc eq ""} continue
    set site [get_sites -quiet $loc]
    if {$site eq ""} continue
    set t [get_tiles -quiet -of $site]
    if {$t ne ""} { set MT($t) 1 }
}
foreach net [get_nets -hierarchical -filter "NAME =~ ${prefix}*"] {
    foreach pip [get_pips -quiet -of $net] { set MT([get_tiles -quiet -of $pip]) 1 }
}
puts "MACRO TILES: [array size MT]"

# ---- 2. emit every pip in an eth tile, tagged by its (full) net name ------
set f  [open eth_macro_gold.routes w]
set fb [open eth_macro_gold.routes.boundary w]
puts $f "# from golden vc707_arpm (arping 10/10); all pips in eth-footprint tiles"
set nnet 0; set npip 0; set nb 0
# TYPE != POWER/GROUND keeps SIGNAL *and* GLOBAL_CLOCK nets (VCC/GND excluded --
# those are rebuilt by nextpnr's const router).  The eth CLOCK nets (txoutclk,
# bufg_userclk/userclk2, ...) must be captured with their FULL distribution
# (BUFG_REBUF/CLK_HROW/HCLK/GCLK), which lies OUTSIDE the MT logic footprint --
# else routeClock (re)builds them on unvalidated GCLK lanes and the 125MHz eth
# domain never clocks on silicon.
foreach net [get_nets -hierarchical -top_net_of_hierarchical_group -filter {TYPE != POWER && TYPE != GROUND}] {
    set pips [get_pips -quiet -of $net]
    if {[llength $pips] == 0} continue
    # Lock only nets FULLY INTERNAL to eth/: every leaf pin under eth/.  This
    # captures macro-internal, framing-internal, and framing<->macro FIFO nets
    # (both endpoints frozen), but skips boundary nets that also touch fresh
    # arp_ctrl / top -- locking their golden pips would fight fresh placement.
    set leafpins [get_pins -quiet -leaf -of $net]
    if {[llength $leafpins] == 0} continue
    set fully_internal 1; set touches_eth 0
    foreach p $leafpins {
        if {[string equal -length $plen $prefix $p]} { set touches_eth 1 } else { set fully_internal 0 }
    }
    # Is this a CLOCK net (routes through dedicated clock tiles)?
    set is_clock 0
    foreach pip $pips {
        set tt [get_property TILE_TYPE [get_tiles -quiet -of $pip]]
        if {[string match "CLK_*" $tt] || [string match "HCLK_*" $tt] || \
            [string match "*BUFG*" $tt] || [string match "CMT_*" $tt] || [string match "*HROW*" $tt]} {
            set is_clock 1; break
        }
    }
    # DATA nets: lock only if FULLY internal to eth/.  CLOCK nets: lock any that
    # TOUCH eth (incl the BOUNDARY clock cpu_clk = msoc_clk, framing-frozen +
    # arp_ctrl-fresh) -- routeClock otherwise routes cpu_clk fresh and grabs the
    # HCLK/GCLK wires golden reserved for txoutclk/gtrefclk -> conflict, wrong
    # clock.  Lock the golden clock BACKBONE (clock tiles) + the eth-footprint
    # sinks; the arp_ctrl last mile (non-clock, non-MT) is left to the router.
    if {$is_clock} {
        if {!$touches_eth} continue
    } else {
        if {!$fully_internal} continue
    }
    set nn [get_property NAME $net]
    set rel $nn
    set emitted 0
    foreach pip $pips {
        set t [get_tiles -quiet -of $pip]
        set tt [get_property TILE_TYPE $t]
        set inclk [expr {[string match "CLK_*" $tt] || [string match "HCLK_*" $tt] || \
                         [string match "*BUFG*" $tt] || [string match "CMT_*" $tt] || [string match "*HROW*" $tt]}]
        if {$is_clock} {
            if {!$inclk && ![info exists MT($t)]} continue
        } else {
            if {![info exists MT($t)]} continue
        }
        set up [get_nodes -quiet -uphill -of $pip]
        set dn [get_nodes -quiet -downhill -of $pip]
        if {$up eq "" || $dn eq ""} continue
        puts $f "$rel $up->$dn"; incr npip; incr emitted
    }
    if {$emitted} { incr nnet }
}
close $f; close $fb
puts "GOLD ROUTES: $nnet nets $npip pips (macro-footprint)"

# ---- 3. placement (unchanged) --------------------------------------------
set fp [open placement_macro_gold.txt w]
set n 0
foreach c [get_cells -hierarchical -filter "IS_PRIMITIVE && PRIMITIVE_LEVEL != MACRO && NAME =~ ${place_prefix}*"] {
    set site [get_property LOC $c]; set bel [get_property BEL $c]
    if {$site ne "" && $bel ne ""} { puts $fp "$c\t$site\t$bel\t[get_property REF_NAME $c]"; incr n }
}
close $fp
puts "GOLD PLACEMENT: $n cells"

# ---- 4. netlist of the WHOLE eth block (framing_top_sgmii + eth_macro) ----
#         so the frozen block's cell names match the golden placement/routes.
write_verilog -force -mode design -cell [get_cells eth] eth_gold_raw.v
puts "GOLD NETLIST DONE (framing_top_sgmii)"
