#!/bin/bash
# OpenTimer STA of an open-flow design.  Cells modelled from the prjxray xc7
# SDF timing (RapidWright ships no 7-series delay model); interconnect from the
# nextpnr FASM pip census as a first-order SPEF.
#
#   run_ot.sh <netlist_y.v> <top> <fasm> <clock_port> <period_ns> [prefix]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
NET=$1; TOP=$2; FASM=$3; CLKPORT=$4; PER=$5; PFX=${6:-des}
OT=$HOME/OpenTimer/bin/ot-shell

python3 "$HERE/sdf2lib.py" "$HERE/xc7fabric.lib" >/dev/null
python3 "$HERE/netlist2ot.py" "$NET" "$TOP" "$HERE/$PFX.v"
python3 "$HERE/route2spef.py" "$FASM" "$HERE/$PFX.conn" "$HERE/$PFX.spef"

# SDC: clock + input slews on every PI + loads on POs
python3 - "$HERE/$PFX.v" "$CLKPORT" "$PER" > "$HERE/$PFX.sdc" <<'PY'
import sys
v, clk, per = sys.argv[1], sys.argv[2], sys.argv[3]
pis=[l.split()[1] for l in open(v) if l.startswith("input ")]
pos=[l.split()[1] for l in open(v) if l.startswith("output ")]
print(f"create_clock -period {per} -name {clk} [get_ports {clk}]")
for p in pis:
    for mm in ("-min","-max"):
        for rf in ("-rise","-fall"):
            print(f"set_input_transition 0.020 {mm} {rf} [get_ports {p}]")
    if p!=clk: print(f"set_input_delay 0.0 -max [get_ports {p}] -clock {clk}")
for p in pos:
    print(f"set_load -pin_load 0.004 [get_ports {p}]")
    print(f"set_output_delay 0.0 -max [get_ports {p}] -clock {clk}")
PY

$OT <<EOF 2>&1 | grep -vE "unit.cpp|celllib.cpp:34|threads|loading|added .* celllib"
set_num_threads 4
read_celllib -min $HERE/xc7fabric.lib
read_celllib -max $HERE/xc7fabric.lib
read_verilog $HERE/$PFX.v
read_spef $HERE/$PFX.spef
read_sdc $HERE/$PFX.sdc
update_timing
report_wns
report_tns
report_timing -num_paths 5
EOF
