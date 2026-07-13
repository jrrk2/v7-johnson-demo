#!/bin/bash
# Overnight re-fuzz orchestrator: waits for 056-pip-rem, pushes its db, then
# runs the specialized INT fuzzers for whatever suspects remain unsolved, and
# finally reports old-vs-new encodings for every re-fuzzed feature.
#
#   nohup bash run_refuzz_chain.sh > /tmp/refuzz_chain.log 2>&1 &
set -u
cd $HOME/prjxray
source settings/virtex7.sh >/dev/null 2>&1
export XRAY_VIVADO_SETTINGS=/home/Xilinx/Vivado/2020.1/settings64.sh
SUS=/home/jonathan/v7-johnson-demo/ethsoc/openflow/pipfuzz/suspect_instances.json

remaining() {  # how many suspects still missing from the real db
python3 - <<'EOF'
import json
sus=set(json.load(open("/home/jonathan/v7-johnson-demo/ethsoc/openflow/pipfuzz/suspect_instances.json")))
sus|={"INT_L.CLK_L0.GCLK_L_B1","INT_L.CLK_L1.GCLK_L_B1","INT_R.CLK0.GCLK_B1_EAST","INT_R.CLK1.GCLK_B1_EAST"}
have=set()
for f in ("segbits_int_l.db","segbits_int_r.db"):
    for ln in open(f"/home/jonathan/prjxray/database/virtex7/{f}"):
        have.add(ln.split()[0])
miss=sorted(sus-have)
print(len(miss))
for m in miss: print(" ",m)
EOF
}

wait_fuzzer() {  # $1 = fuzzer dir; wait for run.ok or a dead loop
    local F=$HOME/prjxray/fuzzers/$1
    echo "[chain] waiting for $1 ..."
    while [ ! -f $F/run.ok ]; do
        sleep 120
        # dead-loop detection: no vivado and no growth for two checks
        if ! pgrep -x vivado >/dev/null; then
            sleep 180
            if ! pgrep -x vivado >/dev/null && [ ! -f $F/run.ok ]; then
                echo "[chain] $1 loop appears DEAD (no vivado, no run.ok)"; return 1
            fi
        fi
    done
    echo "[chain] $1 done"
}

pushdb() {
    ( cd $HOME/prjxray/fuzzers/$1 && make pushdb ) >> /tmp/refuzz_pushdb.log 2>&1 \
      && echo "[chain] $1 pushdb OK" || echo "[chain] $1 pushdb FAILED"
}

run_fuzzer() {
    local F=$HOME/prjxray/fuzzers/$1
    echo "[chain] launching $1"
    ( cd $F && make -j8 run ) > /tmp/refuzz_$1.log 2>&1
    [ -f $F/run.ok ] && echo "[chain] $1 completed" || echo "[chain] $1 FAILED"
    pushdb $1
}

# ---- stage 1: 056-pip-rem (already running when this script starts) ----
wait_fuzzer 056-pip-rem && pushdb 056-pip-rem
echo "[chain] remaining after 056:"; remaining

# ---- stage 2: specialized fuzzers, only if their classes remain ----
LEFT=$(remaining | head -1)
if [ "$LEFT" != "0" ]; then
    for FZ in 052-pip-clkin 053-pip-ctrlin 054-pip-fan-alt 059-pip-byp-bounce 051-pip-imuxlout-bypalts; do
        # does this fuzzer's class appear in the remaining list?
        case $FZ in
          052*) PAT='\.CLK';; 053*) PAT='\.CTRL';;
          054*) PAT='FAN_ALT[0-9]\.GFAN';; 059*) PAT='FAN_ALT[0-9]\.BYP_BOUNCE';;
          051*) PAT='(BYP_ALT|IMUX).*LOGIC_OUTS';;
        esac
        if remaining | tail -n +2 | grep -qE "$PAT"; then run_fuzzer $FZ; fi
    done
fi
# the one bipip
if remaining | tail -n +2 | grep -q "INT_L.LV_L18.LH0"; then run_fuzzer 057-pip-bi; fi

# ---- final report: old vs new encodings ----
echo "[chain] ============ FINAL REPORT ============"
python3 - <<'EOF'
import json
sus=set(json.load(open("/home/jonathan/v7-johnson-demo/ethsoc/openflow/pipfuzz/suspect_instances.json")))
sus|={"INT_L.CLK_L0.GCLK_L_B1","INT_L.CLK_L1.GCLK_L_B1","INT_R.CLK0.GCLK_B1_EAST","INT_R.CLK1.GCLK_B1_EAST"}
def load(f):
    d={}
    for ln in open(f):
        p=ln.split(); d.setdefault(p[0],set()).add(frozenset(p[1:]))
    return d
base="/home/jonathan/prjxray/database/virtex7/"
changed=same=missing=0
for side in ("l","r"):
    old=load(base+f"segbits_int_{side}.db.bak_20260708")
    new=load(base+f"segbits_int_{side}.db")
    for s in sorted(sus):
        if not s.startswith(f"INT_{side.upper()}"): continue
        o=old.get(s); n=new.get(s)
        if n is None: missing+=1; print(f"STILL-MISSING {s}"); continue
        # compare canonical
        if o and any(x in o for x in n): same+=1; print(f"SAME     {s}")
        else:
            changed+=1
            print(f"CHANGED  {s}")
            print(f"   old: {[' '.join(sorted(x)) for x in (o or [])]}")
            print(f"   new: {[' '.join(sorted(x)) for x in n]}")
print(f"\nsummary: changed={changed} same={same} still-missing={missing}")
EOF
echo "[chain] ALL DONE"
