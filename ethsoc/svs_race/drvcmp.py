import re
def norm(n):
    n = n.replace('/', '_').replace('.', '_').replace('[', '_').replace(']', '_')
    n = re.sub(r'_+', '_', n).strip('_')
    return n.lower()

def load(path, strip, is_gold):
    d = {}
    for ln in open(path):
        parts = ln.rstrip('\n').split('|')
        if len(parts) < 5: continue
        ct, cn, pin, drv, ntype = parts
        if is_gold:
            if not cn.startswith('inst/'): continue      # skip inserted top IO bufs
            cn2 = cn[len('inst/'):]
        else:
            if not cn.startswith(strip): continue
            cn2 = cn[len(strip):]
        key = (norm(cn2), pin)
        if ntype == 'GROUND': val = ('CONST0',)
        elif ntype == 'POWER': val = ('CONST1',)
        elif drv == 'UNCONN' or drv == '': val = ('UNCONN',)
        else:
            ds = []
            for one in drv.split(';'):
                if not one: continue
                if one.startswith('PORT:'): ds.append('BOUNDARY')
                else:
                    c, _, p = one.rpartition('.')
                    if is_gold:
                        c2 = c[len('inst/'):] if c.startswith('inst/') else 'BOUNDARY'
                    else:
                        c2 = c[len(strip):] if c.startswith(strip) else 'BOUNDARY'
                    ds.append('BOUNDARY' if c2 == 'BOUNDARY' else norm(c2) + '.' + p)
            val = tuple(sorted(set(ds)))
        d[key] = (ct, val)
    return d

gold = load('/tmp/eb/drvdump/gold.txt', '', True)
svs  = load('/tmp/eb/drvdump/svs.txt', 'i_pcs_pma_258__inst__', False)
print('gold pins:', len(gold), ' svs pins:', len(svs))
gk, sk = set(gold), set(svs)
print('pins only in gold:', len(gk - sk), ' only in svs:', len(sk - gk))
diffs = 0
for k in sorted(gk & sk):
    (gct, gv), (sct, sv) = gold[k], svs[k]
    if gv != sv:
        # BOUNDARY on both sides counts equal even if mixed with same drivers
        if set(gv) == set(sv): continue
        diffs += 1
        if diffs <= 30:
            print('DRVDIFF %s %s.%s\n    gold: %s\n    svs : %s' % (gct, k[0], k[1], gv, sv))
print('DRIVER DIFFS:', diffs)
# sample of one-sided pins
for k in list(sorted(gk - sk))[:8]: print('gold-only pin:', gold[k][0], k)
for k in list(sorted(sk - gk))[:8]: print('svs-only pin:', svs[k][0], k)
