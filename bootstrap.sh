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
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

MODE="apply"          # apply | plan
AUTO_APPROVE="false"
case "${1:-}" in
  -y|--yes)   AUTO_APPROVE="true" ;;
  --plan)     MODE="plan" ;;
  "" )        ;;
  * ) echo "unknown option: $1"; exit 1 ;;
esac

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
for cmd in gcloud gsutil bq terraform python3 java; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command: $cmd"; exit 1; }
done

# ---- python venv with Faker -------------------------------------------------
if [ ! -d .venv ]; then
  echo "[setup] creating python venv + installing Faker..."
  python3 -m venv .venv
  ./.venv/bin/pip install --quiet --upgrade pip
  ./.venv/bin/pip install --quiet -r generators/requirements.txt
fi
PY="${HERE}/.venv/bin/python3"

# ---- generate data ----------------------------------------------------------
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
terraform init -input=false >/dev/null

TF_ARGS=(
  -var "project_id=${PROJECT_ID}"
  -var "region=${REGION}"
  -var "prefix=${PREFIX}"
  -var "enable_cloudsql=${ENABLE_CLOUDSQL}"
  -var "retention_days=${RETENTION_DAYS}"
)

echo "[terraform] planning..."
terraform plan -input=false "${TF_ARGS[@]}"

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
terraform apply -input=false -auto-approve "${TF_ARGS[@]}"

# ---- read outputs -----------------------------------------------------------
BUCKET="$(terraform output -raw bucket_name)"
DATASET="$(terraform output -raw dataset_id)"
SQL_INSTANCE="$(terraform output -raw sql_instance)"
SQL_DB="$(terraform output -raw sql_database)"
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
