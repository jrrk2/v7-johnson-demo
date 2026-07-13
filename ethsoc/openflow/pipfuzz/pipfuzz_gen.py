#!/usr/bin/env python3
"""Generate a targeted pip-fuzz Vivado run: for each suspect pip
(TILETYPE.DST.SRC + concrete instance tile), place a LUT1->LUT1 net nearby
and force its route through the pip with FIXED_ROUTE.  The bitstream then
contains Vivado's ground-truth encoding of that pip; pipfuzz_decode.py
diffs the tile bits against the prjxray segbits prediction.

usage: pipfuzz_gen.py <suspect_instances.json> <out_prefix> [start] [count]
Emits <out_prefix>.v, <out_prefix>.xdc, <out_prefix>.tcl
"""
import json, sys, re

TILEGRID = "/home/jonathan/v7-johnson-demo/deps/prjxray/database/virtex7/xc7vx485t/tilegrid.json"

def main():
    sus = json.load(open(sys.argv[1]))
    pref = sys.argv[2]
    start = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    count = int(sys.argv[4]) if len(sys.argv) > 4 else 4

    grid = json.load(open(TILEGRID))
    coord = {t: (i.get("grid_x"), i.get("grid_y")) for t, i in grid.items()}
    bycoord = {v: k for k, v in coord.items()}

    def nearest_slices(tile, n=2):
        """n SLICE sites in CLB tiles adjacent to the target INT tile."""
        gx, gy = coord[tile]
        out = []
        for dx in (-1, 1, -2, 2):
            t = bycoord.get((gx + dx, gy))
            if t and t.startswith("CLB"):
                out += sorted(grid[t]["sites"])
            if len(out) >= n:
                return out[:n]
        return out[:n]

    # skip CLK-pin pips in this harness (clock nets need dedicated resources)
    items = [(k, v[0]) for k, v in sus.items()
             if v and ".CLK" not in k and "GCLK" not in k]
    items = items[start:start + count]

    nets = []
    for i, (ptype, tile) in enumerate(items):
        tt, dst, src = ptype.split(".")
        sl = nearest_slices(tile, 2)
        if len(sl) < 2:
            print(f"skip {ptype}: no slices near {tile}", file=sys.stderr)
            continue
        nets.append(dict(idx=i, ptype=ptype, tile=tile, dst=dst, src=src,
                         sa=sl[0], sb=sl[1]))

    n = len(nets)
    with open(pref + ".v", "w") as f:
        f.write("// AUTO-GENERATED pip-fuzz harness (pipfuzz_gen.py)\n")
        f.write("module pipfuzz(input wire din, output wire dout);\n")
        f.write(f"  wire [{n-1}:0] mid, q;\n")
        for k in range(n):
            f.write(f'  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2\'b10)) la{k} (.I0(din), .O(mid[{k}]));\n')
            f.write(f'  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2\'b10)) lb{k} (.I0(mid[{k}]), .O(q[{k}]));\n')
        f.write("  assign dout = ^q;\nendmodule\n")

    with open(pref + ".xdc", "w") as f:
        f.write("set_property PACKAGE_PIN AV40 [get_ports din]\n")
        f.write("set_property IOSTANDARD LVCMOS18 [get_ports din]\n")
        f.write("set_property PACKAGE_PIN AM39 [get_ports dout]\n")
        f.write("set_property IOSTANDARD LVCMOS18 [get_ports dout]\n")
        for net in nets:
            k = nets.index(net)
            f.write(f"set_property LOC {net['sa']} [get_cells la{net['idx']}]\n")
            f.write(f"set_property LOC {net['sb']} [get_cells lb{net['idx']}]\n")

    with open(pref + ".tcl", "w") as f:
        f.write(f"""set part xc7vx485tffg1761-2
create_project -force -in_memory -part $part
read_verilog {pref}.v
read_xdc {pref}.xdc
synth_design -top pipfuzz -part $part -flatten_hierarchy none
place_design
route_design
set rpt [open {pref}_pips.txt w]
""")
        for net in nets:
            i = net["idx"]
            tile, dst, src, tt = net["tile"], net["dst"], net["src"], net["ptype"].split(".")[0]
            f.write(f"""
# --- net mid[{i}] through {net['ptype']} @ {tile} ---
set pip [get_pips -quiet "{tile}/{tt}.{src}->>{dst}"]
if {{$pip eq ""}} {{ set pip [get_pips -quiet "{tile}/{tt}.{src}->{dst}"] }}
if {{$pip eq ""}} {{ set pip [get_pips -quiet "{tile}/{tt}.{dst}<<->>{src}"] }}
if {{$pip eq ""}} {{ set pip [get_pips -quiet "{tile}/{tt}.{src}<<->>{dst}"] }}
if {{$pip eq ""}} {{
    puts $rpt "NET mid[{i}] PIP_NOT_FOUND {net['ptype']} {tile}"
}} else {{
    # resolve the net via the driver pin (synth renames wires)
    set net [get_nets -of [get_pins la{i}/O]]
    set_property FIXED_ROUTE {{}} $net
    set_property ROUTE {{}} $net
    set un [get_nodes -uphill   -of $pip]
    set dn [get_nodes -downhill -of $pip]
    # for bidir pips pick orientation matching dst
    if {{[llength $un] != 1}} {{ set un [lindex $un 0] }}
    if {{[llength $dn] != 1}} {{ set dn [lindex $dn 0] }}
    set srcnode  [get_nodes -of [get_site_pins -filter {{DIRECTION == OUT}} -of $net]]
    set sinknode [get_nodes -of [get_site_pins -filter {{DIRECTION == IN}}  -of $net]]
    if {{[catch {{
        set p1 [find_routing_path -from $srcnode -to $un]
        set p2 [find_routing_path -from $dn -to $sinknode]
        set_property FIXED_ROUTE [concat $p1 $p2] $net
        puts $rpt "NET mid[{i}] FORCED {net['ptype']} {tile}"
    }} err]}} {{
        puts $rpt "NET mid[{i}] ROUTE_FAIL {net['ptype']} {tile} :: $err"
    }}
}}
""")
        f.write(f"""
route_design
# dump every net's pips for the decoder
foreach nn [get_nets -hierarchical -filter {{TYPE != POWER && TYPE != GROUND}}] {{
    foreach p [get_pips -quiet -of $nn] {{ puts $rpt "PIP $nn $p" }}
}}
close $rpt
set_property SEVERITY {{Warning}} [get_drc_checks NSTD-1]
set_property SEVERITY {{Warning}} [get_drc_checks UCIO-1]
set_property SEVERITY {{Warning}} [get_drc_checks RTSTAT-5]
set_property SEVERITY {{Warning}} [get_drc_checks RTSTAT-2]
write_bitstream -force {pref}.bit
puts "PIPFUZZ_DONE"
""")
    print(f"generated {pref}.v/.xdc/.tcl with {n} nets:")
    for net in nets:
        print(f"  mid[{net['idx']}] {net['ptype']} @ {net['tile']} (LUTs {net['sa']},{net['sb']})")

main()
