# Open nextpnr's routed design (imported via json2dcp) and check route status
# WITHOUT rerouting — does Vivado see any net as partially/un-routed?
open_checkpoint /tmp/tg_ro.dcp
puts "=== REPORT_ROUTE_STATUS ==="
report_route_status
puts "=== NETS NOT FULLY ROUTED ==="
foreach n [get_nets -hierarchical] {
    set st [get_property ROUTE_STATUS $n]
    if {$st ne "ROUTED" && $st ne "INTRASITE" && $st ne "IMPLICIT"} {
        puts "  NET $n : $st"
    }
}
puts "=== DONE ==="
