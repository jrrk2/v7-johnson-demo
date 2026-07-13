#!/usr/bin/env python3
"""Stamp a Vivado placement dump (placement_flat.txt from dump_sitepips-
style Tcl: name<TAB>site<TAB>SITETYPE.BEL<TAB>REF_NAME) into a yosys JSON
netlist as nextpnr `BEL` attributes ("SITE/BELLEAF").

Name matching: yosys `flatten` joins hierarchy with '.', but components
flattened inside Vivado keep literal '/' in their names — normalise both
sides to one separator before matching.

usage: stamp_placement.py in.json placement.txt out.json
"""
import json, sys, collections

SKIP_REF = {
    # IO handled by nextpnr pack_io from the XDC pin constraints
    'IBUF', 'OBUF', 'OBUFT', 'IOBUF', 'IBUFDS', 'OBUFDS',
    # GT path assigns its own BELs in pack_gt_xc7
    'IBUFDS_GTE2', 'GTXE2_CHANNEL', 'GTXE2_COMMON',
    'GND', 'VCC',
    # macro parents (leaves carry the real placement)
    'RAM32M', 'RAM64M',
}

def norm(name):
    return name.replace('/', '.')

def stitch_out_pad_buffers(top, place):
    """Vivado's netlist models dedicated GT pins as pseudo IBUF/OBUF
    cells placed on IPAD/OPAD sites.  nextpnr's pack_io would treat
    them as fabric IO buffers (and pack_gt expects the raw pad nets) --
    delete them and merge their in/out nets."""
    cells = top['cells']
    victims = []
    for ln in open(place):
        parts = ln.rstrip('\n').split('\t')
        if len(parts) == 4 and (parts[1].startswith('IPAD_') or parts[1].startswith('OPAD_')):
            victims.append(norm(parts[0]))
    bynorm = {norm(k): k for k in cells}
    for v in victims:
        key = bynorm.get(v)
        if key is None:
            continue
        conn = cells[key]['connections']
        bit_i, bit_o = conn['I'][0], conn['O'][0]
        del cells[key]
        # rewrite every use of the buffer output bit to the pad-side bit
        for c in cells.values():
            for pn, bits in c['connections'].items():
                c['connections'][pn] = [bit_i if b == bit_o else b for b in bits]
        for p in top.get('ports', {}).values():
            p['bits'] = [bit_i if b == bit_o else b for b in p['bits']]
        for nn in top.get('netnames', {}).values():
            nn['bits'] = [bit_i if b == bit_o else b for b in nn['bits']]
        print('stitched out pad buffer:', key)

def insert_routethru_luts(top):
    """Vivado feeds a slice's main FF through a LUT *routethru* when both
    the xFF and x5FF of a slot take external (non-slot) data: the main FF
    gets xLUT-as-buffer + xFFMUX.O6, the 5FF gets the X bypass.  nextpnr's
    chipdb has no site-level LUT routethru pips, so emulate with a real
    LUT1 buffer cell pinned at the free LUT bel -- the bitstream encoding
    is identical (buffer INIT + FFMUX.O6)."""
    cells = top['cells']
    # net bit -> driving cell name
    driver = {}
    maxbit = 1
    for cn, c in cells.items():
        dirs = c.get('port_directions', {})
        for pn, bits in c['connections'].items():
            for b in bits:
                if isinstance(b, int) and b > maxbit:
                    maxbit = b
                if dirs.get(pn) == 'output' and isinstance(b, int):
                    driver[b] = cn
    bels = {}   # "SITE/BEL" -> cellname
    for cn, c in cells.items():
        bel = c.get('attributes', {}).get('BEL')
        if bel:
            bels[bel] = cn

    DIRECT_BELS = lambda site, L: [site + '/' + L + '6LUT', site + '/' + L + '5LUT',
                                   site + '/F7AMUX', site + '/F7BMUX',
                                   site + '/F8MUX', site + '/CARRY4']

    def is_direct(site, L, dbit):
        drv = driver.get(dbit)
        if drv is None:
            return True   # const/undriven: no X conflict
        dbel = cells[drv].get('attributes', {}).get('BEL', '')
        return dbel in DIRECT_BELS(site, L)

    inserted = 0

    # MUXF7 legs fed by external signals: Vivado routes the signal THROUGH
    # the (free) local 6LUT into the F7 mux leg.  nextpnr has no site-level
    # LUT routethru, so the router fails with "sink SITEWIRE/.../x6LUT_O6
    # unreachable".  Insert a pinned LUT1 buffer at the free leg.  Which leg
    # belongs to which input pin is resolved by elimination: a driver placed
    # at one of the two local LUTs claims that leg; external inputs take the
    # remaining free leg(s).
    #
    # ORDER MATTERS: the tuple is (I0_leg, I1_leg).  The MUXF7 .I0 input is
    # physically fed by the SECOND LUT of the pair (B6LUT for F7AMUX, D6LUT
    # for F7BMUX), .I1 by the first -- confirmed by Vivado's own F7AMUX
    # placements (the I0 driver sits at B6LUT, the I1 driver at A6LUT).  The
    # ext_pins loop pops free legs in I0,I1 order, so listing I0_leg first
    # places a both-external mux's I0 buffer on the leg I0 actually reads.
    # (Alphabetical order put I0 on the A/C leg -> the buffer's O6 then had to
    # reach the B/D-leg sitewire it was NOT in, an unroutable output->output
    # arc: "...$f7rt$I0$o C6LUT_O6 -> D6LUT_O6".)
    MUX_LEGS = {'F7AMUX': ('B6LUT', 'A6LUT'), 'F7BMUX': ('D6LUT', 'C6LUT')}
    mux_inserted = 0
    for bel, cname in sorted(bels.items()):
        site, leaf = (bel.split('/') + [''])[:2]
        if leaf not in MUX_LEGS:
            continue
        c = cells[cname]
        legs = [site + '/' + L for L in MUX_LEGS[leaf]]
        ext_pins = []
        for p in ('I0', 'I1'):
            bits = c['connections'].get(p, [])
            if not bits or not isinstance(bits[0], int):
                continue
            drv = driver.get(bits[0])
            dbel = cells[drv].get('attributes', {}).get('BEL', '') if drv else ''
            if dbel in legs:
                legs.remove(dbel)
            else:
                ext_pins.append(p)
        free_legs = [l for l in legs if l not in bels]
        if len(ext_pins) > 1:
            print('WARNING: both F7 legs external at %s (%s); leg assignment by '
                  'convention I0->%s' % (bel, cname, MUX_LEGS[leaf][0]))
        for p in ext_pins:
            if not free_legs:
                print('WARNING: no free LUT leg for %s pin %s' % (cname, p))
                break
            lutbel = free_legs.pop(0)
            srcbit = c['connections'][p][0]
            maxbit += 1
            newname = cname + '$f7rt$' + p
            cells[newname] = {
                'hide_name': 0, 'type': 'LUT1',
                'parameters': {'INIT': '10'},
                'attributes': {'BEL': lutbel},
                'port_directions': {'I0': 'input', 'O': 'output'},
                'connections': {'I0': [srcbit], 'O': [maxbit]},
            }
            bels[lutbel] = newname
            driver[maxbit] = newname
            c['connections'][p] = [maxbit]
            top.setdefault('netnames', {})[newname + '$o'] = {
                'hide_name': 1, 'bits': [maxbit], 'attributes': {}}
            mux_inserted += 1
    if mux_inserted:
        print('inserted %d F7-leg routethru LUT1 buffers' % mux_inserted)

    # CARRY4 S[i] legs: the sum-select inputs only reach the carry through
    # the local x6LUT O6.  When Vivado places the S driver in another slice
    # it routes through the (free) local LUT; give nextpnr the same thing
    # as a pinned LUT1 buffer.
    carry_inserted = 0
    LUT_OF_S = ('A6LUT', 'B6LUT', 'C6LUT', 'D6LUT')
    for bel, cname in sorted(bels.items()):
        if not bel.endswith('/CARRY4'):
            continue
        site = bel.split('/')[0]
        c = cells[cname]
        sbits = c['connections'].get('S', [])
        for i, sbit in enumerate(sbits):
            # A CARRY4 S input is a constant ('0'/'1') for unused top bits of
            # an adder/counter (e.g. the 64th bit of a 64-bit counter, S=0).
            # S MUST be driven by the slot's local x6LUT -- there is no internal
            # tie -- so a const S still needs a buffer LUT pinned to that LUT.
            # If we leave it, nextpnr inserts a feed-through LUT that its placer
            # then relocates to a remote slice, leaving the S input fed from a
            # LUT-output sitewire in the WRONG slice (unroutable:
            # "$PACKER_GND_NET$legal$N ... C6LUT_O6 -> D6LUT_O6").  Pin it here,
            # via the same mechanism as the real-net routethrus below.
            is_const = sbit in ('0', '1')
            if not isinstance(sbit, int) and not is_const:
                continue
            lutbel = site + '/' + LUT_OF_S[i]
            if not is_const:
                drv = driver.get(sbit)
                dbel = cells[drv].get('attributes', {}).get('BEL', '') if drv else ''
                if dbel == lutbel:
                    continue
            if lutbel in bels:
                # occupied by another cell: leave to the packer's adoption
                continue
            maxbit += 1
            newname = cname + ('$scrt$%d' % i if is_const else '$srt$%d' % i)
            cells[newname] = {
                'hide_name': 0, 'type': 'LUT1',
                'parameters': {'INIT': '10'},   # O = I0 (buffer); const -> const
                'attributes': {'BEL': lutbel},
                'port_directions': {'I0': 'input', 'O': 'output'},
                'connections': {'I0': [sbit], 'O': [maxbit]},
            }
            bels[lutbel] = newname
            driver[maxbit] = newname
            sbits[i] = maxbit
            top.setdefault('netnames', {})[newname + '$o'] = {
                'hide_name': 1, 'bits': [maxbit], 'attributes': {}}
            carry_inserted += 1
    if carry_inserted:
        print('inserted %d CARRY4-S routethru LUT1 buffers' % carry_inserted)

    for bel, ffname in sorted(bels.items()):
        if not bel.endswith('5FF'):
            continue
        site, leaf = bel.split('/')
        L = leaf[0]
        main = bels.get(site + '/' + L + 'FF')
        if main is None:
            continue
        ff5 = cells[ffname]
        ffm = cells[main]
        d5 = ff5['connections'].get('D', [None])[0]
        dm = ffm['connections'].get('D', [None])[0]
        if not isinstance(d5, int) or not isinstance(dm, int):
            continue
        if is_direct(site, L, d5) or is_direct(site, L, dm):
            continue
        # both external: main FF needs a LUT routethru
        lutbel = None
        for cand in (site + '/' + L + '6LUT', site + '/' + L + '5LUT'):
            if cand not in bels:
                lutbel = cand
                break
        if lutbel is None:
            print('WARNING: no free LUT for routethru at', site, L)
            continue
        maxbit += 1
        newname = main + '$rtlut'
        cells[newname] = {
            'hide_name': 0, 'type': 'LUT1',
            'parameters': {'INIT': '10'},
            'attributes': {'BEL': lutbel},
            'port_directions': {'I0': 'input', 'O': 'output'},
            'connections': {'I0': [dm], 'O': [maxbit]},
        }
        bels[lutbel] = newname
        ffm['connections']['D'] = [maxbit]
        top.setdefault('netnames', {})[newname + '$o'] = {
            'hide_name': 1, 'bits': [maxbit], 'attributes': {}}
        inserted += 1
    print('inserted %d routethru LUT1 buffers' % inserted)


def insert_route_terminal_rtluts(top, routes_path):
    """LUT-routethru cases the both-FFs-external heuristic misses: any main
    FF whose D-net's LOCKED route (fixed-routes file) terminates on a LUT
    input pin of its own slot letter gets a pinned LUT1 buffer at the free
    LUT bel -- Vivado routed through the LUT even though the AX bypass was
    free (the route endpoint disambiguates: LUT input pin vs BYP node)."""
    import re
    cells = top['cells']
    # exact terminal identity: (tile, slice-parity, slot letter).  The half
    # prefix names the slice within the tile pair: double-letter (LL) / M =
    # even-X site, plain L = odd-X (prjxray wire naming; verified against
    # tilegrid).  Site->tile comes from the prjxray tilegrid.
    tilegrid_path = '/home/jonathan/prjxray/database/virtex7/xc7vx485t/tilegrid.json'
    tg = json.load(open(tilegrid_path))
    site2tile = {}
    for tname, td in tg.items():
        for sname, stype in td.get('sites', {}).items():
            if sname.startswith('SLICE_'):
                site2tile[sname] = tname
    rx = re.compile(r'->([^/]+)/CLB[LM]{2}_(LL|M|L)_([A-D])([1-6])$')
    rx_x = re.compile(r'->([^/]+)/CLB[LM]{2}_(LL|M|L)_([A-D])X$')
    term = {}
    xterm = {}
    for line in open(routes_path):
        line = line.split('#')[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            continue
        m = rx.search(parts[1])
        if m:
            even = m.group(2) in ('LL', 'M')
            term.setdefault(norm(parts[0]), set()).add((m.group(1), even, m.group(3)))
        mx = rx_x.search(parts[1])
        if mx:
            even = mx.group(2) in ('LL', 'M')
            xterm.setdefault(norm(parts[0]), set()).add((mx.group(1), even, mx.group(3)))
    if not term:
        return
    # net bit -> normalized net names.  Multi-bit netnames map each bit to
    # the INDEXED name (Vivado route names are per-bit: dpo[1]); single-bit
    # nets get both the plain and the [offset] form.
    bitnames = {}
    for nn, nd in top.get('netnames', {}).items():
        bits = nd.get('bits', [])
        off = nd.get('offset', 0)
        for i, b in enumerate(bits):
            if not isinstance(b, int):
                continue
            bitnames.setdefault(b, []).append(norm('%s[%d]' % (nn, i + off)))
            if len(bits) == 1:
                bitnames.setdefault(b, []).append(norm(nn))
    driver = {}
    maxbit = 1
    for cn, c in cells.items():
        dirs = c.get('port_directions', {})
        for pn, bits in c['connections'].items():
            for b in bits:
                if isinstance(b, int) and b > maxbit:
                    maxbit = b
                if dirs.get(pn) == 'output' and isinstance(b, int):
                    driver[b] = cn
    bels = {}
    for cn, c in cells.items():
        bel = c.get('attributes', {}).get('BEL')
        if bel:
            bels[bel] = cn
    inserted = 0
    for bel, ffname in sorted(bels.items()):
        site, leaf = (bel.split('/') + [''])[:2]
        if len(leaf) != 3 or not leaf.endswith('FF'):
            continue          # main FF bels only (AFF..DFF)
        L = leaf[0]
        ffm = cells[ffname]
        dm = ffm['connections'].get('D', [None])[0]
        if not isinstance(dm, int):
            continue
        drv = driver.get(dm)
        if drv is not None and '$rt' in drv:
            continue          # already buffered by an earlier pass
        dbel = cells[drv].get('attributes', {}).get('BEL', '') if drv else ''
        if dbel.startswith(site + '/' + L):
            continue          # direct in-slot feed
        # does the D-net's locked route end on this slot letter's LUT input
        # of THIS slice (parity-matched within the tile pair)?
        sx = int(site.split('_X')[1].split('Y')[0])
        stile = site2tile.get(site)
        keys = set()
        xkeys = set()
        for nn in bitnames.get(dm, []):
            keys |= term.get(nn, set())
            xkeys |= xterm.get(nn, set())
        slot_key = (stile, sx % 2 == 0, L)
        if stile is None or slot_key not in keys:
            continue
        if slot_key in xkeys:
            continue  # net ALSO reaches this slot's X bypass: FF fed via AX
        # NOTE: no feeds-slot-LUT skip -- Vivado routinely SHARES the input
        # pin between an existing LUT and the FF's route-thru (the free
        # half's INIT reads the shared pin).  AX-bypass-fed FFs never match
        # here anyway: their route terminals are X wires (CLBLM_M_CX), which
        # the [A-D][1-6] pin regex already excludes.
        lutbel = None
        for cand in (site + '/' + L + '6LUT', site + '/' + L + '5LUT'):
            if cand in bels:
                continue
            if cand.endswith('5LUT'):
                # O5 route-thru needs A6 free: skip if the 6LUT occupant
                # uses 6 distinct inputs (A6 carries a real signal)
                occ = bels.get(site + '/' + L + '6LUT')
                if occ is not None:
                    oc = cells[occ]
                    odirs = oc.get('port_directions', {})
                    distinct = set()
                    for pn, bits in oc['connections'].items():
                        if odirs.get(pn) == 'input':
                            for b in bits:
                                distinct.add(b)
                    if len(distinct) >= 6:
                        continue
            lutbel = cand
            break
        if lutbel is None:
            print('WARNING: terminal-rtlut: no usable LUT at', site, L)
            continue
        maxbit += 1
        newname = ffname + '$trt'
        cells[newname] = {
            'hide_name': 0, 'type': 'LUT1',
            'parameters': {'INIT': '10'},
            'attributes': {'BEL': lutbel},
            'port_directions': {'I0': 'input', 'O': 'output'},
            'connections': {'I0': [dm], 'O': [maxbit]},
        }
        bels[lutbel] = newname
        ffm['connections']['D'] = [maxbit]
        top.setdefault('netnames', {})[newname + '$o'] = {
            'hide_name': 1, 'bits': [maxbit], 'attributes': {}}
        inserted += 1
    print('inserted %d route-terminal routethru LUT1 buffers' % inserted)


def main():
    injson, place, outjson = sys.argv[1:4]
    routes_path = sys.argv[4] if len(sys.argv) > 4 else None
    d = json.load(open(injson))
    # top = the unique non-blackbox module
    tops = [m for m, md in d['modules'].items()
            if md.get('cells') and not md.get('attributes', {}).get('blackbox')]
    top = d['modules']['top' if 'top' in d['modules'] else max(tops, key=lambda m: len(d['modules'][m]['cells']))]
    cells = top['cells']
    stitch_out_pad_buffers(top, place)
    bynorm = {}
    for k in cells:
        n = norm(k)
        if n in bynorm:
            print('WARNING: normalised name collision:', n)
        bynorm[n] = k

    stamped = collections.Counter()
    missed = []
    for ln in open(place):
        parts = ln.rstrip('\n').split('\t')
        if len(parts) != 4:
            continue
        name, site, sbel, ref = parts
        if ref in SKIP_REF:
            stamped['skip:' + ref] += 1
            continue
        leaf = sbel.split('.')[-1]
        # nextpnr packs BUFG into a BUFGCTRL cell placed on the BUFGCTRL bel
        if ref in ('BUFG', 'BUFGCE'):
            leaf = 'BUFGCTRL'
        key = bynorm.get(norm(name))
        if key is None:
            missed.append((name, ref))
            continue
        cells[key].setdefault('attributes', {})['BEL'] = site + '/' + leaf
        stamped['bel:' + ref] += 1

    insert_routethru_luts(top)

    if routes_path:

        insert_route_terminal_rtluts(top, routes_path)
    json.dump(d, open(outjson, 'w'))
    total = sum(v for k, v in stamped.items() if k.startswith('bel:'))
    print('stamped %d cells, %d placement rows unmatched' % (total, len(missed)))
    for k, v in sorted(stamped.items()):
        print('  %6d %s' % (v, k))
    for name, ref in missed[:15]:
        print('  MISS %-12s %s' % (ref, name))
    if len(missed) > 15:
        print('  ... %d more misses' % (len(missed) - 15))

if __name__ == '__main__':
    main()
