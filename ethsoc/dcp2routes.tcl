# Dump the routed pips of every macro-internal net from an implemented DCP
# in nextpnr --fixed-routes format:  <net> <tile>/<src_wire>-><tile>/<dst_wire>
#
#   vivado -mode batch -source dcp2routes.tcl \
#          -tclargs <dcp> <hier-prefix> <out.routes>
#   defaults: eth_macro_harness.dcp  u_macro/  eth_macro.routes
#
# Net names in the output are macro-RELATIVE (prefix stripped); the merge
# flow prepends the instance path of the macro in the target design.
# Nets with pins on both sides of the boundary (or on harness ports) go to
# <out>.boundary as comments — they are re-routed by nextpnr in the merge.
# POWER/GROUND nets are skipped (each design re-derives its own tie-offs).
#
# Bidirectional pips are oriented by BFS over nodes from the net's driver
# site pin, so the emitted src->dst direction is the true signal direction.
set dcp    [lindex $argv 0]
set prefix [lindex $argv 1]
set out    [lindex $argv 2]
if {$dcp eq ""}    { set dcp eth_macro_harness.dcp }
if {$prefix eq ""} { set prefix {u_macro/} }
if {$out eq ""}    { set out eth_macro.routes }

open_checkpoint $dcp

set f  [open $out w]
set fb [open ${out}.boundary w]
puts $f "# nextpnr fixed-routes from $dcp (prefix $prefix, names macro-relative)"
puts $fb "# boundary/partial nets (re-routed at merge time) from $dcp"

set plen [string length $prefix]
set nnet 0; set nboundary 0; set npip 0; set nskip_unrouted 0; set nobfs 0

foreach net [get_nets -hierarchical -top_net_of_hierarchical_group \
                 -filter "TYPE == SIGNAL && NAME =~ ${prefix}*"] {
    set pins [get_pins -quiet -leaf -of $net]
    if {[llength $pins] == 0} { continue }
    # boundary test: any leaf pin outside the prefix, or a design port on the net
    set internal 1
    foreach p $pins {
        if {![string equal -length $plen $prefix $p]} { set internal 0; break }
    }
    if {[llength [get_ports -quiet -of $net]] > 0} { set internal 0 }
    set rel [string range $net $plen end]
    if {!$internal} {
        puts $fb "# BOUNDARY $rel"
        incr nboundary
        continue
    }
    set pips [get_pips -quiet -of $net]
    if {[llength $pips] == 0} { continue }
    set status [get_property ROUTE_STATUS $net]
    if {$status ne "ROUTED" && $status ne "INTRASITE"} {
        incr nskip_unrouted
        continue
    }

    # ---- orient pips: BFS from the driver node over the pip set ----------
    set drvpin [get_pins -quiet -leaf -filter {DIRECTION == OUT} -of $net]
    set drvsp  [get_site_pins -quiet -of $drvpin]
    set known  {}
    foreach n [get_nodes -quiet -of $drvsp] { lappend known $n }
    array unset seen
    foreach n $known { set seen($n) 1 }

    # pip records: {pipname up down bidir}
    set recs {}
    foreach pip $pips {
        set up   [get_nodes -quiet -uphill   -of $pip]
        set down [get_nodes -quiet -downhill -of $pip]
        set bid  [get_property IS_DIRECTIONAL $pip]
        lappend recs [list $pip $up $down $bid]
    }
    set remaining $recs
    set ordered {}
    set progress 1
    while {$progress && [llength $remaining] > 0} {
        set progress 0
        set next {}
        foreach r $remaining {
            lassign $r pip up down directional
            if {[info exists seen($up)]} {
                lappend ordered [list $pip 0]
                if {![info exists seen($down)]} { set seen($down) 1 }
                set progress 1
            } elseif {!$directional && [info exists seen($down)]} {
                lappend ordered [list $pip 1]
                if {![info exists seen($up)]} { set seen($up) 1 }
                set progress 1
            } else {
                lappend next $r
            }
        }
        set remaining $next
    }
    if {[llength $remaining] > 0} {
        # driver-side BFS failed for some pips (e.g. GT/pad-side or stubs):
        # emit them un-oriented as-parsed and note it
        incr nobfs
        foreach r $remaining { lappend ordered [list [lindex $r 0] 0] }
    }

    # emit NODE names (Vivado's node name = the canonical/root wire), not the
    # pip's tile-local wire names: nextpnr's getWireByName only reaches pips
    # through the node-canonical wire — tile-local member names resolve to
    # pipless wires and produce pip-misses (the 7232-miss arp failure mode)
    array unset pnodes
    foreach r $recs { lassign $r pip up down bid; set pnodes($pip) [list $up $down] }
    foreach rec $ordered {
        lassign $rec pip rev
        lassign $pnodes($pip) up down
        if {$up eq "" || $down eq ""} {
            puts $fb "# NONODE $rel $pip"
            continue
        }
        if {$rev} { set t $up; set up $down; set down $t }
        puts $f "$rel $up->$down"
        incr npip
    }
    incr nnet
}
close $f
close $fb
puts "dcp2routes: $nnet internal nets, $npip pips -> $out"
puts "dcp2routes: $nboundary boundary nets -> ${out}.boundary; $nskip_unrouted unrouted skipped; $nobfs nets with unBFSed pips"
