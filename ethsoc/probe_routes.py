# nextpnr --run probe: check how many pips in a --fixed-routes file resolve
# in the chipdb (wire lookup + downhill/uphill pip scan), independent of nets.
#   ROUTES_FILE=eth_macro.routes nextpnr-xilinx --chipdb ... --json <any.json> \
#       --run probe_routes.py
# (the python API has no getWireByName, so build a name map by full wire scan)
import os

fn = os.environ.get("ROUTES_FILE", "eth_macro.routes")
pips = []           # (src_name, dst_name)
wanted = set()
for line in open(fn):
    line = line.split('#')[0].strip()
    if not line:
        continue
    parts = line.split()
    if len(parts) != 2 or '->' not in parts[1]:
        continue
    s, d = parts[1].split('->', 1)
    pips.append((s, d))
    wanted.add(s)
    wanted.add(d)

print("PROBE_ROUTES: scanning wires for %d names..." % len(wanted))
name2wire = {}
for w in ctx.getWires():
    s = str(w)
    if s in wanted:
        name2wire[s] = w

tot = len(pips)
wire_miss = pip_miss = ok = 0
miss_examples = []
for s, d in pips:
    if s not in name2wire or d not in name2wire:
        wire_miss += 1
        if len(miss_examples) < 12:
            miss_examples.append("WIRE %s->%s [%s]" %
                (s, d, ("S" if s not in name2wire else "") + ("D" if d not in name2wire else "")))
        continue
    src, dst = name2wire[s], name2wire[d]
    found = False
    for p in ctx.getPipsDownhill(src):
        if str(ctx.getPipDstWire(p)) == d:
            found = True
            break
    if not found:
        for p in ctx.getPipsUphill(dst):
            if str(ctx.getPipSrcWire(p)) == s:
                found = True
                break
    if found:
        ok += 1
    else:
        pip_miss += 1
        if len(miss_examples) < 12:
            miss_examples.append("PIP  %s->%s" % (s, d))

print("PROBE_ROUTES: total=%d ok=%d wire_miss=%d pip_miss=%d" % (tot, ok, wire_miss, pip_miss))
for m in miss_examples:
    print("  miss:", m)
