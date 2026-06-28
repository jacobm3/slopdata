#!/usr/bin/env bash
# ============================================================================
# run_synthea.sh -- generate synthetic medical patient records with Synthea
# (MITRE's open-source synthetic patient generator). Produces realistic CSVs:
# patients.csv (names, SSN, addresses, DOB), conditions, medications, etc.
#
# Usage: run_synthea.sh <out_dir> <size e.g. 10MB>
# ============================================================================
set -euo pipefail

OUT_DIR="$1"
SIZE="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="${HERE}/.synthea"        # cache the jar so re-runs are fast
JAR="${CACHE_DIR}/synthea-with-dependencies.jar"
JAR_URL="https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar"

mkdir -p "$OUT_DIR" "$CACHE_DIR"

# --- work out how many patients to generate from the byte target -------------
# Empirically each patient produces very roughly ~80 KB of CSV across all the
# Synthea output files. We divide the target by that to pick a population size.
# ponytail: rough constant; medical volume is "patients", not exact bytes. If
# you need a precise size, bump/trim the divisor here.
BYTES="$(python3 "${HERE}/common.py" bytes "$SIZE")"
COUNT=$(( BYTES / 80000 ))
[ "$COUNT" -lt 1 ] && COUNT=1

echo "synthea: generating ~${COUNT} patients (target ${SIZE})"

# --- fetch the jar once ------------------------------------------------------
if [ ! -f "$JAR" ]; then
  echo "synthea: downloading generator jar (one-time)..."
  curl -fsSL -o "$JAR" "$JAR_URL"
fi

# --- run headless ------------------------------------------------------------
# -p N            population size
# csv export on, FHIR export off (CSV is what we load into BigQuery)
# output goes to a temp dir we then copy the CSVs out of.
WORK="$(mktemp -d)"
java -jar "$JAR" \
  -p "$COUNT" \
  --exporter.baseDirectory "$WORK" \
  --exporter.csv.export true \
  --exporter.fhir.export false \
  --exporter.hospital.fhir.export false \
  --exporter.practitioner.fhir.export false \
  Massachusetts >/dev/null

# Copy the generated CSVs into our output dir.
cp "$WORK"/csv/*.csv "$OUT_DIR"/
rm -rf "$WORK"

echo "synthea: wrote $(ls "$OUT_DIR"/*.csv | wc -l) CSV files to $OUT_DIR"
