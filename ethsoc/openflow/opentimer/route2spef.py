#!/usr/bin/env python3
"""Emit a proper OpenTimer SPEF from the netlist connectivity (<pref>.conn),
assigning each net a lumped interconnect delay.  Elmore delay driver->sink =
R * C_sink; with C_sink fixed we pick R so R*C = the per-net routing delay.

Per-net delay = (design-wide avg INT hops/net) * (avg per-hop delay), from the
open FASM pip census -- a first-order model (we lack per-net routing; refine
with RapidWright node lengths later).  Long-line-heavy designs get a larger
average automatically.  Units: NS / PF / KOHM (R*C in kohm*pf = ns).

usage: route2spef.py <fasm> <pref.conn> <out.spef>
"""
import sys, os, json

fasm, conn, out = sys.argv[1], sys.argv[2], sys.argv[3]
C = 0.001

# Vivado-calibrated routing-delay-vs-fanout (netchar.py from golden SDF); else
# fall back to a flat per-hop estimate from the FASM pip census.
_nc = os.path.join(os.path.dirname(os.path.abspath(__file__)), "netchar.json")
NETCHAR = json.load(open(_nc)) if os.path.exists(_nc) else None
conns = [l.rstrip("\n").split("\t") for l in open(conn) if l.strip()]
nnets = len(conns)

if NETCHAR:
    byfo = NETCHAR["byfanout"]; base, slope = NETCHAR["fit"]
    def net_delay(fo):
        return byfo.get(str(fo), base + slope*fo)
    print(f"[route2spef] Vivado-calibrated routing (netchar.json): "
          f"delay(ns)~{base:.3f}+{slope:.5f}*fanout, p95={NETCHAR['p95_all']}ns", file=sys.stderr)
else:
    HOP, LONG = 0.060, 0.120
    npips = longp = 0
    for ln in open(fasm, errors="replace"):
        p = ln.strip().split(".")
        if len(p) == 3 and p[0].startswith(("INT_L", "INT_R")):
            npips += 1
            if any(k in p[1]+p[2] for k in ("LH","LV","LVB","6BEG","6END")): longp += 1
    avg_hops = max(1.0, npips / max(1, nnets))
    avg_hop_delay = (longp*LONG + (npips-longp)*HOP) / max(1, npips)
    NETD = avg_hops * avg_hop_delay
    def net_delay(fo): return NETD
    print(f"[route2spef] flat model {NETD:.3f} ns/net (no netchar.json)", file=sys.stderr)

with open(out, "w") as f:
    f.write('*SPEF "IEEE 1481-1998"\n*DESIGN "open"\n*DATE "x"\n*VENDOR "x"\n')
    f.write('*PROGRAM "route2spef"\n*VERSION "1.0"\n*DESIGN_FLOW ""\n')
    f.write('*DIVIDER /\n*DELIMITER :\n*BUS_DELIMITER [ ]\n')
    f.write('*T_UNIT 1 NS\n*C_UNIT 1 PF\n*R_UNIT 1 KOHM\n*L_UNIT 1 HENRY\n\n')
    for row in conns:
        net, drv = row[0], row[1]
        snks = row[2].split() if len(row) > 2 else []
        def pinref(x):
            return x[5:] if x.startswith("PORT:") else x   # OpenTimer: port pin = bare name
        drvp = pinref(drv)
        snkps = [pinref(s) for s in snks]
        fo = len(snkps)
        # CLOCK nets ride the dedicated low-skew global tree, NOT fabric routing:
        # the generic fanout-lumped delay (~2ns at fanout ~900) fabricates huge
        # capture-clock skew and fake hold violations.  Detect by sink pins.
        nck = sum(1 for s in snks if s.endswith(":C") or s.endswith(":CLK"))
        is_clock = fo > 0 and nck * 2 >= fo
        R = (0.050 if is_clock else net_delay(fo)) / C   # Elmore R*C (ns)
        totcap = C * fo
        f.write(f"*D_NET {net} {totcap:.5f}\n*CONN\n")
        # NB: test the PORT: prefix, NOT ":" in the raw string -- "PORT:x" itself
        # contains a colon, so the old test emitted port drivers as instance pins
        # (*I) and broke the RC tree of every port-driven (cut-BUFG) clock net.
        f.write(f"*P {drvp} O\n" if drv.startswith("PORT:") else f"*I {drvp} O\n")
        for s in snks:
            f.write(f"*P {pinref(s)} I\n" if s.startswith("PORT:") else f"*I {pinref(s)} I\n")
        f.write("*CAP\n")
        f.write(f"1 {drvp} 0.0\n")
        for i, s in enumerate(snkps, start=2):
            f.write(f"{i} {s} {C:.5f}\n")
        f.write("*RES\n")
        for i, s in enumerate(snkps, start=1):
            f.write(f"{i} {drvp} {s} {R:.4f}\n")
        f.write("*END\n\n")
print(f"[route2spef] wrote {out} ({nnets} nets)", file=sys.stderr)
