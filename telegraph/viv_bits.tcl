# Bitgen nextpnr's EXACT routing (imported via json2dcp) using Vivado's correct
# bit encoding.  Preserve nextpnr's routing; only fix the 2 json2dcp import
# artifacts (sysclk_n unrouted, VCC antenna).  If the resulting bitstream works
# (JRRK) -> nextpnr routing is correct, prjxray v7 segbits are the bug.
open_checkpoint /tmp/tg_ro.dcp
puts "=== before fixup ==="
report_route_status
# Route only what nextpnr left unrouted, preserving everything already routed.
route_design -preserve
puts "=== after preserve-route ==="
report_route_status
set_property SEVERITY {Warning} [get_drc_checks RTSTAT-*]
write_bitstream -force /tmp/tg_ro_vivbits.bit
puts "VIV_BITS_DONE"
