#!/usr/bin/env bash
# Build the json2dcp wire-name + PIP oracle for the part using RapidWright.
# Independent of the segbits in the device DB (RapidWright Device model), but
# released alongside the DB so the whole flow ships from one tag.
#
#   PART=xc7vx485tffg1761-2 JDR=/path/to/json_drc-portable ./build-oracle.sh
#
# Output: $OUT_DIR/<part>.oracle.txt.gz + .sha256
set -euo pipefail

TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # device-db-tools/
PART="${PART:-xc7vx485tffg1761-2}"
OUT_DIR="${OUT_DIR:-$TOOLS/build}"
JDR="${JDR:-$HOME/json_drc-portable}"
mkdir -p "$OUT_DIR"

export RAPIDWRIGHT_PATH="${RAPIDWRIGHT_PATH:-$JDR/data}"
RW_JAR="$(ls "$JDR"/lib/rapidwright-*-standalone-lin64.jar 2>/dev/null | head -1 || true)"
GSON_JAR="$(ls "$JDR"/lib/gson-*.jar 2>/dev/null | head -1 || true)"
DRC_JAR="$JDR/lib/rapidwright_json_drc.jar"
for f in "$RW_JAR" "$GSON_JAR" "$DRC_JAR" "$RAPIDWRIGHT_PATH"; do
  [ -e "$f" ] || { echo "ERROR: missing $f — set JDR to your json_drc-portable" >&2; exit 1; }
done

OUT="$OUT_DIR/$PART.oracle.txt.gz"
PREBUILT="${PREBUILT_ORACLE:-$JDR/oracle/$PART.oracle.txt.gz}"
echo "== oracle build =="
echo "  part        : $PART"
echo "  rapidwright : $(basename "$RW_JAR")"
# The oracle is RapidWright-derived (DB-independent), so a prebuilt one for the
# same part is identical.  Prefer building fresh; fall back to a prebuilt copy
# if BuildWireOracle isn't compiled into the jar.
if java -cp "$DRC_JAR:$RW_JAR:$GSON_JAR" dev.fpga.rapidwright.BuildWireOracle "$PART" "$OUT" 2>/dev/null; then
  echo "  built fresh from RapidWright"
elif [ -f "$PREBUILT" ]; then
  echo "  BuildWireOracle not in jar — reusing prebuilt $PREBUILT (DB-independent)"
  cp "$PREBUILT" "$OUT"
else
  echo "ERROR: BuildWireOracle unavailable and no prebuilt oracle at $PREBUILT" >&2
  echo "       (compile src/BuildWireOracle.java into $DRC_JAR, or set PREBUILT_ORACLE)" >&2
  exit 1
fi
( cd "$OUT_DIR" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "  done: $OUT ($(du -h "$OUT" | cut -f1))"
