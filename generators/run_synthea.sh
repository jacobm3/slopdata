#!/usr/bin/env bash

# ============================================================================
# Welcome to run_synthea.sh!
# This script is a helper that downloads and runs a special program called "Synthea".
# Synthea is like a "fake hospital simulator". It creates realistic, but completely
# made-up, medical records for fake patients (names, addresses, illnesses, etc.).
# We use this to test if our security tools can find sensitive medical data.
# ============================================================================

# Safety rules: stop if anything goes wrong.
set -euo pipefail

# These are inputs given to the script when it is run.
# OUT_DIR: Where should we put the fake patient files?
# SIZE: How much data (in megabytes or gigabytes) do we want?
OUT_DIR="$1"
SIZE="$2"

# Find out where this script is located.
HERE="$(cd "$(dirname "$0")" && pwd)"

# We will create a hidden folder called ".synthea" to store the Synthea program.
# This way, we only download it once and can reuse it.
CACHE_DIR="${HERE}/.synthea"
JAR="${CACHE_DIR}/synthea-with-dependencies.jar"

# This is the internet address where we can download the Synthea program.
JAR_URL="https://github.com/synthetichealth/synthea/releases/download/master-branch-latest/synthea-with-dependencies.jar"

# Make sure the output folder and the cache folder actually exist.
# If they don't, create them.
mkdir -p "$OUT_DIR" "$CACHE_DIR"

# --- Figure out how many patients to make ---
# Each fake patient produces about 80 Kilobytes of data.
# We want to match the user's requested SIZE.
# So, we convert the size (like "10MB") into bytes using our "common.py" helper,
# and then divide that by 80,000 to get the number of patients we need.
BYTES="$(python3 "${HERE}/common.py" bytes "$SIZE")"
COUNT=$(( BYTES / 80000 ))

# We must generate at least 1 patient!
[ "$COUNT" -lt 1 ] && COUNT=1

echo "synthea: generating ~${COUNT} patients (target ${SIZE})"

# --- Download the Synthea program if we don't have it yet ---
if [ ! -f "$JAR" ]; then
  echo "synthea: downloading generator jar (one-time)..."
  # curl is like a mini web browser that downloads files from the internet.
  curl -fsSL -o "$JAR" "$JAR_URL"
fi

# --- Run the Synthea program ---
# We create a temporary "work" folder that will be deleted later.
WORK="$(mktemp -d)"

# We run the Synthea program using Java.
# -jar "$JAR": Run this Java program.
# -p "$COUNT": Make this many patients.
# --exporter.baseDirectory "$WORK": Put the results in our temp folder.
# --exporter.csv.export true: We want CSV files (like spreadsheets).
# --exporter.fhir.export false (and others): Turn off other formats we don't need.
# "Massachusetts": Generate patients that live in Massachusetts (Synthea requires a state).
# >/dev/null: Hide the messy output of the program so it doesn't clutter the screen.
java -jar "$JAR" \
  -p "$COUNT" \
  --exporter.baseDirectory "$WORK" \
  --exporter.csv.export true \
  --exporter.fhir.export false \
  --exporter.hospital.fhir.export false \
  --exporter.practitioner.fhir.export false \
  Massachusetts >/dev/null

# Copy the generated CSV files from the temp folder to our official output folder.
cp "$WORK"/csv/*.csv "$OUT_DIR"/

# Clean up and delete the temporary folder.
rm -rf "$WORK"

# Tell the user we are done and how many files we made.
echo "synthea: wrote $(ls "$OUT_DIR"/*.csv | wc -l) CSV files to $OUT_DIR"
