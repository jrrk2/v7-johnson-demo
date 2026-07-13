set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog pilot.v
read_xdc pilot.xdc
synth_design -top pipfuzz -part $part -flatten_hierarchy none
place_design
route_design
set rpt [open pilot_pips.txt w]

# --- net mid[0] through INT_L.CTRL_L1.NW6END2 @ INT_L_X132Y21 ---
set pip [get_pips -quiet "INT_L_X132Y21/INT_L.NW6END2->>CTRL_L1"]
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X132Y21/INT_L.NW6END2->CTRL_L1"] }
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X132Y21/INT_L.CTRL_L1<<->>NW6END2"] }
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X132Y21/INT_L.NW6END2<<->>CTRL_L1"] }
if {$pip eq ""} {
    puts $rpt "NET mid[0] PIP_NOT_FOUND INT_L.CTRL_L1.NW6END2 INT_L_X132Y21"
} else {
    # resolve the net via the driver pin (synth renames wires)
    set net [get_nets -of [get_pins la0/O]]
    set_property FIXED_ROUTE {} $net
    set_property ROUTE {} $net
    set un [get_nodes -uphill   -of $pip]
    set dn [get_nodes -downhill -of $pip]
    # for bidir pips pick orientation matching dst
    if {[llength $un] != 1} { set un [lindex $un 0] }
    if {[llength $dn] != 1} { set dn [lindex $dn 0] }
    set srcnode  [get_nodes -of [get_site_pins -filter {DIRECTION == OUT} -of $net]]
    set sinknode [get_nodes -of [get_site_pins -filter {DIRECTION == IN}  -of $net]]
    if {[catch {
        set p1 [find_routing_path -from $srcnode -to $un]
        set p2 [find_routing_path -from $dn -to $sinknode]
        set_property FIXED_ROUTE [concat $p1 $p2] $net
        puts $rpt "NET mid[0] FORCED INT_L.CTRL_L1.NW6END2 INT_L_X132Y21"
    } err]} {
        puts $rpt "NET mid[0] ROUTE_FAIL INT_L.CTRL_L1.NW6END2 INT_L_X132Y21 :: $err"
    }
}

# --- net mid[1] through INT_L.EE4BEG2.LVB_L0 @ INT_L_X124Y14 ---
set pip [get_pips -quiet "INT_L_X124Y14/INT_L.LVB_L0->>EE4BEG2"]
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X124Y14/INT_L.LVB_L0->EE4BEG2"] }
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X124Y14/INT_L.EE4BEG2<<->>LVB_L0"] }
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X124Y14/INT_L.LVB_L0<<->>EE4BEG2"] }
if {$pip eq ""} {
    puts $rpt "NET mid[1] PIP_NOT_FOUND INT_L.EE4BEG2.LVB_L0 INT_L_X124Y14"
} else {
    # resolve the net via the driver pin (synth renames wires)
    set net [get_nets -of [get_pins la1/O]]
    set_property FIXED_ROUTE {} $net
    set_property ROUTE {} $net
    set un [get_nodes -uphill   -of $pip]
    set dn [get_nodes -downhill -of $pip]
    # for bidir pips pick orientation matching dst
    if {[llength $un] != 1} { set un [lindex $un 0] }
    if {[llength $dn] != 1} { set dn [lindex $dn 0] }
    set srcnode  [get_nodes -of [get_site_pins -filter {DIRECTION == OUT} -of $net]]
    set sinknode [get_nodes -of [get_site_pins -filter {DIRECTION == IN}  -of $net]]
    if {[catch {
        set p1 [find_routing_path -from $srcnode -to $un]
        set p2 [find_routing_path -from $dn -to $sinknode]
        set_property FIXED_ROUTE [concat $p1 $p2] $net
        puts $rpt "NET mid[1] FORCED INT_L.EE4BEG2.LVB_L0 INT_L_X124Y14"
    } err]} {
        puts $rpt "NET mid[1] ROUTE_FAIL INT_L.EE4BEG2.LVB_L0 INT_L_X124Y14 :: $err"
    }
}

# --- net mid[2] through INT_L.EE4BEG3.LOGIC_OUTS_L11 @ INT_L_X134Y21 ---
set pip [get_pips -quiet "INT_L_X134Y21/INT_L.LOGIC_OUTS_L11->>EE4BEG3"]
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X134Y21/INT_L.LOGIC_OUTS_L11->EE4BEG3"] }
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X134Y21/INT_L.EE4BEG3<<->>LOGIC_OUTS_L11"] }
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X134Y21/INT_L.LOGIC_OUTS_L11<<->>EE4BEG3"] }
if {$pip eq ""} {
    puts $rpt "NET mid[2] PIP_NOT_FOUND INT_L.EE4BEG3.LOGIC_OUTS_L11 INT_L_X134Y21"
} else {
    # resolve the net via the driver pin (synth renames wires)
    set net [get_nets -of [get_pins la2/O]]
    set_property FIXED_ROUTE {} $net
    set_property ROUTE {} $net
    set un [get_nodes -uphill   -of $pip]
    set dn [get_nodes -downhill -of $pip]
    # for bidir pips pick orientation matching dst
    if {[llength $un] != 1} { set un [lindex $un 0] }
    if {[llength $dn] != 1} { set dn [lindex $dn 0] }
    set srcnode  [get_nodes -of [get_site_pins -filter {DIRECTION == OUT} -of $net]]
    set sinknode [get_nodes -of [get_site_pins -filter {DIRECTION == IN}  -of $net]]
    if {[catch {
        set p1 [find_routing_path -from $srcnode -to $un]
        set p2 [find_routing_path -from $dn -to $sinknode]
        set_property FIXED_ROUTE [concat $p1 $p2] $net
        puts $rpt "NET mid[2] FORCED INT_L.EE4BEG3.LOGIC_OUTS_L11 INT_L_X134Y21"
    } err]} {
        puts $rpt "NET mid[2] ROUTE_FAIL INT_L.EE4BEG3.LOGIC_OUTS_L11 INT_L_X134Y21 :: $err"
    }
}

# --- net mid[3] through INT_L.FAN_ALT3.BYP_BOUNCE5 @ INT_L_X150Y15 ---
set pip [get_pips -quiet "INT_L_X150Y15/INT_L.BYP_BOUNCE5->>FAN_ALT3"]
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X150Y15/INT_L.BYP_BOUNCE5->FAN_ALT3"] }
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X150Y15/INT_L.FAN_ALT3<<->>BYP_BOUNCE5"] }
if {$pip eq ""} { set pip [get_pips -quiet "INT_L_X150Y15/INT_L.BYP_BOUNCE5<<->>FAN_ALT3"] }
if {$pip eq ""} {
    puts $rpt "NET mid[3] PIP_NOT_FOUND INT_L.FAN_ALT3.BYP_BOUNCE5 INT_L_X150Y15"
} else {
    # resolve the net via the driver pin (synth renames wires)
    set net [get_nets -of [get_pins la3/O]]
    set_property FIXED_ROUTE {} $net
    set_property ROUTE {} $net
    set un [get_nodes -uphill   -of $pip]
    set dn [get_nodes -downhill -of $pip]
    # for bidir pips pick orientation matching dst
    if {[llength $un] != 1} { set un [lindex $un 0] }
    if {[llength $dn] != 1} { set dn [lindex $dn 0] }
    set srcnode  [get_nodes -of [get_site_pins -filter {DIRECTION == OUT} -of $net]]
    set sinknode [get_nodes -of [get_site_pins -filter {DIRECTION == IN}  -of $net]]
    if {[catch {
        set p1 [find_routing_path -from $srcnode -to $un]
        set p2 [find_routing_path -from $dn -to $sinknode]
        set_property FIXED_ROUTE [concat $p1 $p2] $net
        puts $rpt "NET mid[3] FORCED INT_L.FAN_ALT3.BYP_BOUNCE5 INT_L_X150Y15"
    } err]} {
        puts $rpt "NET mid[3] ROUTE_FAIL INT_L.FAN_ALT3.BYP_BOUNCE5 INT_L_X150Y15 :: $err"
    }
}

route_design
# dump every net's pips for the decoder
foreach nn [get_nets -hierarchical -filter {TYPE != POWER && TYPE != GROUND}] {
    foreach p [get_pips -quiet -of $nn] { puts $rpt "PIP $nn $p" }
}
close $rpt
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks RTSTAT-5]
set_property SEVERITY {Warning} [get_drc_checks RTSTAT-2]
write_bitstream -force pilot.bit
puts "PIPFUZZ_DONE"
