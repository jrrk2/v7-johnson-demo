# device-db-tools

Original tooling that **builds and releases** the openXC7 Virtex-7 device
database artifacts. Kept here, in the demo repo, **separate from the database
itself** — the database (`openXC7/database-virtex7`) is a derivative of
licensed tools (prjxray fuzzer output, ISC), whereas this code is ours, under
this repo's licence. The recipes only *reference* the DB and the upstream
build tools (nextpnr-xilinx `bbaexport.py`/`bbasm`, RapidWright) by path.

## Recipes (`recipes/`)

| script | builds | from |
|---|---|---|
| `build-chipdb.sh` | nextpnr chipdb `xc7vx485t.bin` | the DB, via `bbaexport.py --xray <DB>` + `bbasm` |
| `build-oracle.sh` | json2dcp wire oracle `*.oracle.txt.gz` | RapidWright (`BuildWireOracle`) |
| `cut-release.sh`  | a synchronized release set (chipdb + oracle + DB tarball + stamped `manifest.json` + `SHA256SUMS`) | a clean DB commit |

All take env overrides; defaults assume the layout on the build machine:

```sh
DB_DIR=$HOME/prjxray/database/virtex7          # the database-virtex7 checkout
NEXTPNR_DIR=$HOME/v7-johnson-demo/deps/nextpnr-xilinx
JDR=$HOME/json_drc-portable                    # for the oracle (RapidWright)
```

Outputs go to `build/` (gitignored).

## Release flow

1. Commit + tag the DB in `openXC7/database-virtex7` (`device-db-YYYY-MM-DD`).
2. `DB_DIR=… recipes/cut-release.sh` — builds the chipdb + oracle from that
   commit, stamps `manifest.json` with the DB commit, the **nextpnr-xilinx
   commit the chipdb's `.bba` format requires**, and asset SHA256s.
3. Attach `build/release/*` to a GitHub release on the same tag.

One tag ⇒ DB commit + chipdb + oracle, so they can never drift apart (the old
failure mode of separate chipdb/DB tags on different tool-fork repos).

## manifest.json

Provenance template stamped per-release by `cut-release.sh`. Pins the
nextpnr-xilinx commit (`c80c431a…`) whose chipdb `.bba` format this targets —
the easy-to-miss compatibility constraint.
