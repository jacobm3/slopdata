#!/usr/bin/env bash
# ============================================================================
# bootstrap.sh -- ONE command to generate fake sensitive data and deploy it to
# GCP so Sensitive Data Protection (SDP) / Security Command Center can find it.
#
#   1. reads your settings from config.env
#   2. generates the data locally (free)
#   3. shows you a Terraform plan and asks before creating anything
#   4. creates the bucket / BigQuery dataset / Cloud SQL instance
#   5. uploads the data and loads it into BigQuery and the database
#
# Run it from the repo root, e.g. in GCP Cloud Shell:
#     ./bootstrap.sh           # apply, with a confirmation prompt
#     ./bootstrap.sh -y        # skip the confirmation (full auto)
#     ./bootstrap.sh --plan    # generate + plan only, don't create anything
#     ./bootstrap.sh -f        # force regeneration of data
#     ./bootstrap.sh -y -f     # full auto, force data regeneration
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

MODE="apply"          # apply | plan
AUTO_APPROVE="false"
FORCE_REGEN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      AUTO_APPROVE="true"
      shift
      ;;
    --plan)
      MODE="plan"
      shift
      ;;
    -f|--force)
      FORCE_REGEN="true"
      shift
      ;;
    *)
      echo "unknown option: $1"
      exit 1
      ;;
  esac
done

# ---- load config ------------------------------------------------------------
[ -f config.env ] || { echo "config.env not found"; exit 1; }
# shellcheck disable=SC1091
source config.env

# Default the project to the active gcloud project if not set.
if [ -z "${PROJECT_ID:-}" ]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi
[ -n "$PROJECT_ID" ] || { echo "No PROJECT_ID set and no active gcloud project."; exit 1; }

echo "=============================================================="
echo " Synthetic data demo"
echo "   project : $PROJECT_ID"
echo "   prefix  : $PREFIX"
echo "   region  : $REGION"
echo "   cloudsql: $ENABLE_CLOUDSQL"
echo "=============================================================="

# ---- prerequisites ----------------------------------------------------------
# Note: terraform is checked/installed separately below. We don't put it in this
# loop because GCP Cloud Shell ships a /google/bin/terraform *stub* that only
# prints install instructions -- command -v would find it and pass, but it isn't
# a working terraform.
for cmd in gcloud gsutil bq python3 java; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command: $cmd"; exit 1; }
done

# ---- terraform install ------------------------------------------------------
# We can't trust `command -v terraform` (see the Cloud Shell stub note above), so
# we go by the dpkg package instead. If the real terraform package isn't
# installed, install it from HashiCorp's official apt repo. Terraform is not in
# Debian's own repos (licensing), so the HashiCorp repo is required.
if dpkg -s terraform >/dev/null 2>&1; then
  echo "[setup] terraform already installed via apt."
else
  echo "[setup] installing terraform from HashiCorp apt repo..."
  # 2>/dev/null silences Cloud Shell's "packages won't persist" apt warning;
  # the [ -x "$TERRAFORM" ] guard below still catches a genuine install failure.
  sudo apt-get install -y -qq gnupg curl lsb-release >/dev/null 2>&1
  # Add HashiCorp's signing key (--yes so re-runs overwrite the existing keyring).
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  # Add the apt repo for this Debian release.
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -qq 2>/dev/null
  sudo apt-get install -y -qq terraform >/dev/null 2>&1
fi

# Call terraform by the dpkg-installed path so the /google/bin stub (which comes
# earlier on Cloud Shell's PATH) can't shadow the real binary.
TERRAFORM="$(dpkg -L terraform | grep -m1 '/bin/terraform$')"
[ -x "$TERRAFORM" ] || { echo "terraform install failed"; exit 1; }

# ---- python venv with Faker -------------------------------------------------
if [ ! -d .venv ]; then
  echo "[setup] creating python venv + installing Faker..."
  python3 -m venv .venv
  ./.venv/bin/pip install --quiet --upgrade pip
  ./.venv/bin/pip install --quiet -r generators/requirements.txt
fi
PY="${HERE}/.venv/bin/python3"

# ---- generate data ----------------------------------------------------------
# Check if data directory exists and is not empty
DATA_EXISTS=false
if [ -d data ] && [ "$(ls -A data 2>/dev/null)" ]; then
  DATA_EXISTS=true
fi

if [ "${FORCE_REGEN}" = "true" ] || [ "${DATA_EXISTS}" = "false" ]; then
  echo "[generate] producing data into ./data ..."
  rm -rf data
  mkdir -p data
  export PYTHONPATH="${HERE}/generators"   # so generators can import common.py

  [ "${ENABLE_CUSTOMERS}" = "true" ] && "$PY" generators/gen_customers.py  data/customers "$VOL_CUSTOMERS"
  [ "${ENABLE_FINANCIAL}" = "true" ] && "$PY" generators/gen_financial.py  data/financial "$VOL_FINANCIAL"
  [ "${ENABLE_PATENTS}"   = "true" ] && "$PY" generators/gen_patents.py    data/patents   "$VOL_PATENTS"
  [ "${ENABLE_SECRETS}"   = "true" ] && "$PY" generators/gen_secrets.py    data/secrets   "$VOL_SECRETS"
  [ "${ENABLE_MEDICAL}"   = "true" ] && bash  generators/run_synthea.sh    data/medical   "$VOL_MEDICAL"

  echo "[generate] done. Local data size:"
  du -sh data
else
  echo "[generate] ./data already exists and is not empty. Skipping generation."
  echo "[generate] Use -f or --force to force regeneration."
fi

# ---- enable the GCP APIs we need (idempotent) -------------------------------
echo "[gcp] enabling required APIs (one-time, may take a minute)..."
gcloud services enable \
  storage.googleapis.com \
  bigquery.googleapis.com \
  sqladmin.googleapis.com \
  dlp.googleapis.com \
  --project "$PROJECT_ID" --quiet

# ---- terraform --------------------------------------------------------------
cd terraform
"$TERRAFORM" init -input=false >/dev/null

TF_ARGS=(
  -var "project_id=${PROJECT_ID}"
  -var "region=${REGION}"
  -var "prefix=${PREFIX}"
  -var "enable_cloudsql=${ENABLE_CLOUDSQL}"
  -var "retention_days=${RETENTION_DAYS}"
)

echo "[terraform] planning..."
"$TERRAFORM" plan -input=false "${TF_ARGS[@]}"

if [ "$MODE" = "plan" ]; then
  echo "[terraform] --plan given; stopping before apply."
  exit 0
fi

if [ "$AUTO_APPROVE" != "true" ]; then
  echo
  read -r -p "Create these resources in project ${PROJECT_ID}? [y/N] " ans
  case "$ans" in
    y|Y|yes) ;;
    *) echo "aborted."; exit 0 ;;
  esac
fi

echo "[terraform] applying..."
"$TERRAFORM" apply -input=false -auto-approve "${TF_ARGS[@]}"

# ---- read outputs -----------------------------------------------------------
BUCKET="$("$TERRAFORM" output -raw bucket_name)"
DATASET="$("$TERRAFORM" output -raw dataset_id)"
SQL_INSTANCE="$("$TERRAFORM" output -raw sql_instance)"
SQL_DB="$("$TERRAFORM" output -raw sql_database)"
cd "$HERE"

# ---- upload data to the bucket ----------------------------------------------
echo "[upload] copying data to gs://${BUCKET}/ ..."
gsutil -m cp -r data/* "gs://${BUCKET}/"

# ---- load CSVs into BigQuery (autodetect schema) ----------------------------
bq_load() {
  local table="$1" uri="$2"
  echo "[bigquery] loading ${table} ..."
  bq --location="$REGION" load --quiet --replace --autodetect \
    --source_format=CSV "${PROJECT_ID}:${DATASET}.${table}" "$uri" || \
    echo "  (skipped ${table}: source not present)"
}
[ "${ENABLE_CUSTOMERS}" = "true" ] && bq_load customers "gs://${BUCKET}/customers/customers.csv"
[ "${ENABLE_FINANCIAL}" = "true" ] && bq_load financial "gs://${BUCKET}/financial/financial.csv"
[ "${ENABLE_PATENTS}"   = "true" ] && bq_load patents   "gs://${BUCKET}/patents/patents.csv"
if [ "${ENABLE_MEDICAL}" = "true" ]; then
  # Load the highest-signal Synthea tables (these carry the patient PII).
  bq_load medical_patients    "gs://${BUCKET}/medical/patients.csv"
  bq_load medical_conditions  "gs://${BUCKET}/medical/conditions.csv"
  bq_load medical_medications "gs://${BUCKET}/medical/medications.csv"
fi

# ---- import customer data into Cloud SQL (server-side from the bucket) -------
if [ "${ENABLE_CLOUDSQL}" = "true" ] && [ "${ENABLE_CUSTOMERS}" = "true" ]; then
  echo "[cloudsql] importing customers into ${SQL_INSTANCE}/${SQL_DB} ..."
  gcloud sql import sql "$SQL_INSTANCE" "gs://${BUCKET}/customers/customers.sql" \
    --database="$SQL_DB" --project="$PROJECT_ID" --quiet
fi

# ---- done -------------------------------------------------------------------
cat <<EOF

==============================================================
 Done. Resources created (all prefixed "${PREFIX}"):
   bucket  : gs://${BUCKET}
   dataset : ${PROJECT_ID}:${DATASET}
$( [ "${ENABLE_CLOUDSQL}" = "true" ] && echo "   cloudsql: ${SQL_INSTANCE} (db: ${SQL_DB})" )

 Next: turn on Sensitive Data Protection discovery
   Console -> Security -> Sensitive Data Protection -> Discovery
   Create scan configs for Cloud Storage, BigQuery$( [ "${ENABLE_CLOUDSQL}" = "true" ] && echo " and Cloud SQL" ).
   Profiles populate in SCC within ~minutes-to-hours.

 To tear everything down (and stop any cost):
   ./destroy.sh
==============================================================
EOF
