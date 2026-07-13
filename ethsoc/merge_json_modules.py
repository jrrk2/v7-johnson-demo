#!/usr/bin/env python3
"""Union-merge two yosys jsons at module level: the user design plus the
pass-through eth_macro netlist.  eth_macro (the real implementation) always
comes from the macro json, replacing the user side's blackbox stub;
duplicated library blackboxes are harmless and kept from the user json."""
import json, sys
user, macro, out = sys.argv[1:4]
ju = json.load(open(user))
jm = json.load(open(macro))
mods = ju['modules']
for name, m in jm['modules'].items():
    if name == 'framing_top_sgmii' or name not in mods:
        mods[name] = m
# only 'top' keeps the top attribute
for name, m in mods.items():
    if name != 'top':
        m.get('attributes', {}).pop('top', None)
json.dump(ju, open(out, 'w'))
print("merged: %d modules" % len(mods))
