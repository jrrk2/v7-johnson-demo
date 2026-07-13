#!/usr/bin/env python3
"""Emit fixed-routes lines locking the intra-slice SRLC32E cascade DI-mux pips.

nextpnr's SRLC32E bel exposes no Q31 wire, so patch_netlist rewrites the cascade
shiftout onto .Q (== C?LUT_O6).  nextpnr then sees a fabric net driver.Q ->
sink.D that must ride the dedicated intra-slice DI mux (e.g. C6LUT_O6 ->
BDI1MUX_OUT) which it cannot route on its own.  Lock that one site pip per
cascade net so router2 uses the golden cascade path.

usage: gen_srl_cascade_routes.py stamped.json >> routes
"""
import json, sys, re

def main():
    j = json.load(open(sys.argv[1]))
    top = j['modules']['top']
    cells = top['cells']

    def belpos(cell):  # -> (slice, pos) e.g. ('SLICE_X220Y19','C')
        bel = cells[cell].get('attributes', {}).get('BEL', '')
        m = re.match(r'(SLICE_X\d+Y\d+)/([A-D])6LUT', bel)
        return (m.group(1), m.group(2)) if m else (None, None)

    # bit -> netname
    bit2net = {}
    for name, nn in top['netnames'].items():
        for b in nn.get('bits', []):
            if isinstance(b, int):
                bit2net[b] = name

    # bit -> driver SRL, list of sink SRLs (same-slice cascade)
    driver = {}
    users = {}
    for n, c in cells.items():
        if c['type'] != 'SRLC32E':
            continue
        pd = c.get('port_directions', {})
        for port, bits in c['connections'].items():
            for b in bits:
                if not isinstance(b, int):
                    continue
                if pd.get(port) == 'output' and port in ('Q', 'Q31'):
                    driver[b] = n
                elif port == 'D':
                    users.setdefault(b, []).append(n)

    n_emitted = 0
    for b, dn in driver.items():
        for un in users.get(b, []):
            ds, dp = belpos(dn)
            us, up = belpos(un)
            if ds is None or us is None or ds != us:
                continue
            net = bit2net.get(b)
            if net is None:
                continue
            src = "SITEWIRE/%s/%s6LUT_O6" % (ds, dp)
            dst = "SITEWIRE/%s/%sDI1MUX_OUT" % (us, up)
            print("%s %s->%s" % (net, src, dst))
            n_emitted += 1
    sys.stderr.write("gen_srl_cascade_routes: emitted %d cascade DI-mux locks\n" % n_emitted)

if __name__ == '__main__':
    main()
