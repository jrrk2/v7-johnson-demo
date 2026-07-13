# Dump every used site pip of every used SLICE to a side file that
# dcp2fasm consumes (3rd argument).  Works around a RapidWright gap:
# dangling OUTMUX site pips (mux programmed, output pin unrouted) are
# present in the DCP/XDEF but missing from SiteInst.getUsedSitePIPs().
#
# usage: vivado -mode batch -source dump_sitepips.tcl \
#               -tclargs <design.dcp> <out.txt>
set dcp [lindex $argv 0]
set out [lindex $argv 1]
open_checkpoint $dcp
set fp [open $out w]
foreach site [get_sites -filter {IS_USED && SITE_TYPE =~ SLICE*}] {
    foreach sp [get_site_pips -of $site -filter {IS_USED}] {
        puts $fp $sp
    }
}
close $fp
puts "SITEPIPS_DONE"
