#!/usr/bin/env bash
# Regenerate the nextpnr-xilinx chipdb FROM the device DB (the xc7 / Project
# X-Ray path: bbaexport.py --xray <DB> + bbasm).  The .bba binary format is
# tied to a specific nextpnr-xilinx commit (see manifest.json) — build with
# that checkout or the .bin will be rejected/misread by nextpnr.
#
# This is ORIGINAL tooling and lives in the demo repo, separate from the DB
# (a derivative-of-licensed-tools artifact).  It only references the DB by path.
#
#   DB_DIR=/path/to/database-virtex7 NEXTPNR_DIR=/path/to/nextpnr-xilinx ./build-chipdb.sh
#
# Output: $OUT_DIR/<device>.bin(.zst) + .sha256
set -euo pipefail

TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # device-db-tools/
PART="${PART:-xc7vx485tffg1761-2}"
DEVICE="${DEVICE:-xc7vx485t}"                              # bba/bin base name
DB_DIR="${DB_DIR:-$HOME/prjxray/database/virtex7}"         # the database-virtex7 checkout
NEXTPNR_DIR="${NEXTPNR_DIR:-$HOME/v7-johnson-demo/deps/nextpnr-xilinx}"
OUT_DIR="${OUT_DIR:-$TOOLS/build}"
PY="${PY:-$(command -v pypy3 || command -v python3)}"      # pypy3 is much faster
mkdir -p "$OUT_DIR"

BBAEXPORT="$NEXTPNR_DIR/xilinx/python/bbaexport.py"
BBASM="$NEXTPNR_DIR/build/bbasm"
CONSTIDS="$NEXTPNR_DIR/xilinx/constids.inc"
META="$NEXTPNR_DIR/xilinx/external/nextpnr-xilinx-meta/virtex7"
[ -e "$DB_DIR/$PART/part.yaml" ] || { echo "ERROR: $DB_DIR/$PART/part.yaml not found — is DB_DIR the virtex7 family dir and PART correct?" >&2; exit 1; }
for f in "$BBAEXPORT" "$BBASM" "$CONSTIDS" "$META"; do
  [ -e "$f" ] || { echo "ERROR: missing $f — set NEXTPNR_DIR to a built nextpnr-xilinx" >&2; exit 1; }
done

NPNR_COMMIT="$(git -C "$NEXTPNR_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "== chipdb build =="
echo "  part        : $PART"
echo "  DB (--xray) : $DB_DIR"
echo "  nextpnr     : $NPNR_COMMIT  (must match manifest.json)"

BBA="$OUT_DIR/$DEVICE.bba"
BIN="$OUT_DIR/$DEVICE.bin"
if [ -n "${REUSE_CHIPDB:-}" ] && [ -f "$BIN.zst" ]; then
  echo "  REUSE_CHIPDB: keeping existing $BIN.zst ($(du -h "$BIN.zst" | cut -f1))"
  exit 0
fi
echo "  bbaexport -> $BBA"
"$PY" "$BBAEXPORT" --xray "$DB_DIR" --metadata "$META" \
    --device "$PART" --constids "$CONSTIDS" --bba "$BBA"
echo "  bbasm     -> $BIN"
"$BBASM" --l "$BBA" "$BIN"
zstd -19 -f "$BIN" -o "$BIN.zst" >/dev/null
( cd "$OUT_DIR" && sha256sum "$(basename "$BIN").zst" > "$(basename "$BIN").zst.sha256" )
echo "  done: $BIN.zst ($(du -h "$BIN.zst" | cut -f1))"
