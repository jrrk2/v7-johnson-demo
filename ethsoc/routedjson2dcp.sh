#!/bin/bash
# nextpnr routed.json (--write) -> Vivado DCP via RapidWright json2dcp.
# Preprocesses nextpnr output for json2dcp's strictness:
#   - netnames entries for dangling bits (conn bits with no netname)
#   - X_ORIG_TYPE for never-repacked primitives (its type IS the Unisim),
#     except nextpnr-internal PSEUDO_* cells
#   - empty ROUTING attr on synthesized netnames
# Usage: routedjson2dcp.sh <routed.json> <out.dcp>
set -eu
IN=$1; OUT=$2
JDR=$HOME/json_drc-portable
RW=$(ls $JDR/lib/rapidwright-*-standalone-lin64.jar | head -1)
GSON=$(ls $JDR/lib/gson-*.jar | head -1)
FIX=$(mktemp /tmp/j2d_fix_XXXX.json)
python3 - "$IN" "$FIX" <<'PY'
import json,re,sys
j=json.load(open(sys.argv[1]))
mod=max(j["modules"].values(),key=lambda m:len(m.get("cells",{})))
cells=mod["cells"]; nn=mod.setdefault("netnames",{})
known=set()
for e in nn.values():
    for b in e.get("bits",[]):
        if isinstance(b,int): known.add(b)
dang=set()
for c in cells.values():
    for bl in c.get("connections",{}).values():
        for b in bl:
            if isinstance(b,int) and b not in known: dang.add(b)
for b in sorted(dang):
    nn[f"$dangling${b}"]={"hide_name":1,"bits":[b],"attributes":{}}
nt=0
for c in cells.values():
    a=c.setdefault("attributes",{})
    if "X_ORIG_TYPE" not in a and re.fullmatch(r"[A-Z][A-Z0-9_]*",c["type"]) \
       and not c["type"].startswith("PSEUDO_"):
        a["X_ORIG_TYPE"]=c["type"]; nt+=1
nr=0
for e in nn.values():
    a=e.setdefault("attributes",{})
    if "ROUTING" not in a: a["ROUTING"]=""; nr+=1
json.dump(j,open(sys.argv[2],"w"))
print(f"preprocess: {len(dang)} dangling nets, {nt} X_ORIG_TYPE tags, {nr} ROUTING attrs")
PY
XRAY_WIRE_ORACLE=$JDR/oracle/xc7vx485tffg1761-2.oracle.txt.gz \
RAPIDWRIGHT_PATH=$JDR/data \
java -Xmx8g -cp "$JDR/lib/rapidwright_json_drc.jar:$RW:$GSON" \
  dev.fpga.rapidwright.json2dcp xc7vx485tffg1761-2 "$FIX" "$OUT" 2>&1 | grep -vE "^\s*\(|^INT_" | tail -5
rm -f "$FIX"
ls -l "$OUT"
