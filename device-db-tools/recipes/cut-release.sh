#!/usr/bin/env bash
# Cut one synchronized release: build the chipdb + oracle from a given DB
# commit, bundle the DB tarball, stamp manifest.json (DB commit + nextpnr
# commit + asset sha256s), and emit SHA256SUMS.  Run against a clean, committed
# DB tree so the recorded DB commit fully describes the assets.
#
#   DB_DIR=/path/to/database-virtex7 ./cut-release.sh
#
# Output: $OUT_DIR/release/  (attach its contents to a GitHub release tagged
# the same as the DB tag).
set -euo pipefail

TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # device-db-tools/
DB_DIR="${DB_DIR:-$HOME/prjxray/database/virtex7}"
NEXTPNR_DIR="${NEXTPNR_DIR:-$HOME/v7-johnson-demo/deps/nextpnr-xilinx}"
PART="${PART:-xc7vx485tffg1761-2}"
DEVICE="${DEVICE:-xc7vx485t}"
OUT_DIR="${OUT_DIR:-$TOOLS/build}"
REL="$OUT_DIR/release"
mkdir -p "$REL"

if [ -n "$(git -C "$DB_DIR" status --porcelain)" ]; then
  echo "WARNING: DB tree not clean — the recorded DB commit won't fully describe the assets." >&2
fi
DB_COMMIT="$(git -C "$DB_DIR" rev-parse HEAD)"
NPNR_COMMIT="$(git -C "$NEXTPNR_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"

echo "== building artifacts =="
PART="$PART" DEVICE="$DEVICE" DB_DIR="$DB_DIR" NEXTPNR_DIR="$NEXTPNR_DIR" OUT_DIR="$OUT_DIR" \
  "$TOOLS/recipes/build-chipdb.sh"
PART="$PART" OUT_DIR="$OUT_DIR" "$TOOLS/recipes/build-oracle.sh"

# Bundle the DB itself as a tarball asset (convenience for non-git consumers).
DB_TAR="$REL/prjxray-database-virtex7.tar.zst"
echo "== bundling DB tarball =="
( cd "$DB_DIR/.." && tar --use-compress-program='zstd -19 --long=27 -T0' \
    --exclude='virtex7/.git' -cf "$DB_TAR" virtex7 )

cp "$OUT_DIR/$DEVICE.bin.zst" "$REL/"
cp "$OUT_DIR/$PART.oracle.txt.gz" "$REL/"

sha256 () { sha256sum "$1" | cut -d' ' -f1; }
CHIPDB_SHA="$(sha256 "$REL/$DEVICE.bin.zst")"
ORACLE_SHA="$(sha256 "$REL/$PART.oracle.txt.gz")"
DBTAR_SHA="$(sha256 "$DB_TAR")"

# Stamp manifest.json -> release/manifest.json
DB_COMMIT="$DB_COMMIT" NPNR_COMMIT="$NPNR_COMMIT" PART="$PART" DEVICE="$DEVICE" \
CHIPDB_SHA="$CHIPDB_SHA" ORACLE_SHA="$ORACLE_SHA" DBTAR_SHA="$DBTAR_SHA" \
python3 - "$TOOLS/manifest.json" "$REL/manifest.json" <<'PY'
import json, os, sys
src, dst = sys.argv[1], sys.argv[2]
m = json.load(open(src))
m["db"]["commit"] = os.environ["DB_COMMIT"]
da = m["derived_artifacts"]
da["chipdb"]["file"] = os.environ["DEVICE"] + ".bin.zst"
da["chipdb"]["nextpnr_xilinx_commit"] = os.environ["NPNR_COMMIT"]
da["chipdb"]["sha256"] = os.environ["CHIPDB_SHA"]
da["oracle"]["file"] = os.environ["PART"] + ".oracle.txt.gz"
da["oracle"]["sha256"] = os.environ["ORACLE_SHA"]
m.setdefault("db_tarball", {})
m["db_tarball"]["file"] = "prjxray-database-virtex7.tar.zst"
m["db_tarball"]["sha256"] = os.environ["DBTAR_SHA"]
json.dump(m, open(dst, "w"), indent=2)
open(dst, "a").write("\n")
PY

( cd "$REL" && sha256sum manifest.json "$DEVICE.bin.zst" "$PART.oracle.txt.gz" \
    "$(basename "$DB_TAR")" > SHA256SUMS )
echo "== release assets in $REL =="
ls -lh "$REL"
echo "DB commit: $DB_COMMIT   nextpnr: $NPNR_COMMIT"
