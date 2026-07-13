#!/bin/bash
# OpenTimer STA (setup + HOLD) of a FLATTENED nextpnr/yosys json design.
#   run_ot_json.sh <flat.json> <fasm> <period_ns> [pfx]
# json2ot: json -> pfx.{v,lib,conn}; route2spef: fasm+conn -> pfx.spef;
# SDC auto-generated: create_clock on every PI that drives an FF :C pin
# (clock buffers are CUT by json2ot so clock nets surface as PIs), input
# slews on all PIs, -min AND -max io delays so hold tests exist.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
J=$1; FASM=$2; PER=$3; PFX=${4:-des}
OT=$HOME/OpenTimer/bin/ot-shell
cd "$HERE"
python3 json2ot.py "$J" "$PFX"
# EARLY/min-corner liberty (hold analysis): same netlist, fast-corner calib
if [ -f "$HERE/calib_min.json" ]; then
  OT_CALIB="$HERE/calib_min.json" OT_LIB_OUT="$HERE/${PFX}_min.lib" python3 json2ot.py "$J" "$PFX"
fi
python3 route2spef.py "$FASM" "$PFX.conn" "$PFX.spef"
python3 - "$PFX" "$PER" > "$PFX.sdc" <<'PY'
import sys
pfx, per = sys.argv[1], float(sys.argv[2])
clks = set(); pis = []; pos = []
for l in open(pfx + ".conn"):
    p = l.rstrip("\n").split("\t")
    if len(p) < 2: continue
    drv = p[1]; snks = p[2].split() if len(p) > 2 else []
    if drv.startswith("PORT:"):
        pis.append(drv[5:])
        if any(s.endswith(":C") for s in snks): clks.add(drv[5:])
    for s in snks:
        if s.startswith("PORT:"): pos.append(s[5:])
# OpenTimer needs set_input_delay AND set_input_transition on the CLOCK ports
# themselves (all four el/rf combos, -clock self) to seed clock arrivals --
# without them every downstream at/slack is nan (cf. example/simple/simple.sdc).
first = None; cname = {}
for i, c in enumerate(sorted(clks)):
    print(f"create_clock -period {per} -name ck{i} [get_ports {c}]")
    cname[c] = f"ck{i}"
    if first is None: first = f"ck{i}"
def io4(cmd, val, p, clk):
    for mm in ("-min", "-max"):
        for rf in ("-rise", "-fall"):
            print(f"{cmd} {val} {mm} {rf} [get_ports {p}] -clock {clk}")
for p in pis:
    clk = cname.get(p, first)
    if not clk: continue
    io4("set_input_delay", "0", p, clk)
    io4("set_input_transition", "0.020", p, clk)
for p in pos:
    print(f"set_load -pin_load 0.004 [get_ports {p}]")
    if first:
        io4("set_output_delay", "0", p, first)
PY
$OT <<EOF 2>&1 | grep -vE "unit.cpp|celllib.cpp:34|threads|loading|added .* celllib"
set_num_threads 4
read_celllib -min $HERE/$([ -f $HERE/${PFX}_min.lib ] && echo ${PFX}_min.lib || echo $PFX.lib)
read_celllib -max $HERE/$PFX.lib
read_verilog $HERE/$PFX.v
read_spef $HERE/$PFX.spef
read_sdc $HERE/$PFX.sdc
update_timing
report_wns
report_tns
report_timing -num_paths 3
report_timing -num_paths 3 -min
EOF
