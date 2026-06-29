#!/usr/bin/env bash

# ============================================================================
# Welcome to bootstrap.sh!
# This is the "Main Button" script. You press this button, and it sets up
# everything for the demo.
#
# It does these things:
# 1. Reads your settings from "config.env".
# 2. Creates fake data on your computer (for free!).
# 3. Sets up Google Cloud resources (like storage buckets and databases) using Terraform.
# 4. Uploads the fake data to Google Cloud.
# ============================================================================

# Safety rules: stop if anything goes wrong.
# -e: Stop if a command fails.
# -u: Stop if we use an undefined variable.
# -o pipefail: Stop if any command in a pipeline fails.
set -euo pipefail

# Find out where this script is located on the computer.
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# Decide what mode we are in.
# "apply" means "actually build things".
# "plan" means "just show me what you would build, but don't build it yet".
MODE="apply"          
AUTO_APPROVE="false"

# Look at the first option the user typed after the script name (e.g., ./bootstrap.sh -y)
case "${1:-}" in
  -y|--yes)   AUTO_APPROVE="true" ;; # If they said -y, don't ask for confirmation.
  --plan)     MODE="plan" ;;         # If they said --plan, just show the plan.
  "" )        ;;                     # If they said nothing, use defaults.
  * ) echo "unknown option: $1"; exit 1 ;; # If they typed something weird, stop.
esac

# ---- Load Settings ------------------------------------------------------------
# Check if the "config.env" file exists. If not, stop.
[ -f config.env ] || { echo "config.env not found"; exit 1; }
# Load the settings from "config.env" so we can use them as variables.
# shellcheck disable=SC1091
source config.env

# We need a Google Cloud Project ID to know where to build things.
# If it's not set in config.env, we ask the 'gcloud' tool what the current active project is.
if [ -z "${PROJECT_ID:-}" ]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi
# If we STILL don't have a project ID, we have to stop.
[ -n "$PROJECT_ID" ] || { echo "No PROJECT_ID set and no active gcloud project."; exit 1; }

# Print out a nice summary of what we are about to do.
echo "=============================================================="
echo " Synthetic data demo"
echo "   project : $PROJECT_ID"
echo "   prefix  : $PREFIX"
echo "   region  : $REGION"
echo "   cloudsql: $ENABLE_CLOUDSQL"
echo "=============================================================="

# ---- Check for Required Tools -----------------------------------------------
# We need these tools installed on the computer to run.
# gcloud: Google Cloud CLI (to talk to Google Cloud)
# gsutil: Google Cloud Storage tool (to upload files)
# bq: BigQuery tool (to load data into tables)
# python3: Python programming language (to run our data generators)
# java: Java (needed for the Synthea medical data generator)
for cmd in gcloud gsutil bq python3 java; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command: $cmd"; exit 1; }
done

# ---- Install Terraform ------------------------------------------------------
# Terraform is the tool that builds our Google Cloud resources.
# We check if it is already installed.
if dpkg -s terraform >/dev/null 2>&1; then
  echo "[setup] terraform already installed via apt."
else
  # If not installed, we download and install it.
  echo "[setup] installing terraform from HashiCorp apt repo..."
  # Install some helper tools for adding the repository.
  sudo apt-get install -y -qq gnupg curl lsb-release >/dev/null 2>&1
  # Get the official security key for Terraform.
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  # Add the Terraform repository to our list of software sources.
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  # Update the list and install Terraform.
  sudo apt-get update -qq 2>/dev/null
  sudo apt-get install -y -qq terraform >/dev/null 2>&1
fi

# Find where the real Terraform binary was installed.
TERRAFORM="$(dpkg -L terraform | grep -m1 '/bin/terraform$')"
[ -x "$TERRAFORM" ] || { echo "terraform install failed"; exit 1; }

# ---- Setup Python Virtual Environment ----------------------------------------
# A virtual environment (.venv) is like an isolated sandbox for Python.
# It prevents our project's python packages from messing up the rest of the system.
if [ ! -d .venv ]; then
  echo "[setup] creating python venv + installing Faker..."
  # Create the sandbox.
  python3 -m venv .venv
  # Upgrade 'pip' (the Python package installer).
  ./.venv/bin/pip install --quiet --upgrade pip
  # Install 'Faker' (used to generate fake names/addresses) and other packages.
  ./.venv/bin/pip install --quiet -r generators/requirements.txt
fi
# Define a shortcut to use our sandbox Python.
PY="${HERE}/.venv/bin/python3"

# ---- Generate Fake Data -----------------------------------------------------
echo "[generate] producing data into ./data ..."
# Delete any old data we generated before, and make a fresh folder.
rm -rf data
mkdir -p data
# Tell Python where to find our helper scripts.
export PYTHONPATH="${HERE}/generators"   

# Run the generator scripts if they are enabled in config.env.
# We pass the output folder and the amount of data we want.
[ "${ENABLE_CUSTOMERS}" = "true" ] && "$PY" generators/gen_customers.py  data/customers "$VOL_CUSTOMERS"
[ "${ENABLE_FINANCIAL}" = "true" ] && "$PY" generators/gen_financial.py  data/financial "$VOL_FINANCIAL"
[ "${ENABLE_PATENTS}"   = "true" ] && "$PY" generators/gen_patents.py    data/patents   "$VOL_PATENTS"
[ "${ENABLE_SECRETS}"   = "true" ] && "$PY" generators/gen_secrets.py    data/secrets   "$VOL_SECRETS"
[ "${ENABLE_MEDICAL}"   = "true" ] && bash  generators/run_synthea.sh    data/medical   "$VOL_MEDICAL"

echo "[generate] done. Local data size:"
# Show how much data we made.
du -sh data

# ---- Enable Google Cloud APIs -----------------------------------------------
# Before we can use Google Cloud services, we have to turn them on (enable them).
echo "[gcp] enabling required APIs (one-time, may take a minute)..."
gcloud services enable \
  storage.googleapis.com \
  bigquery.googleapis.com \
  sqladmin.googleapis.com \
  dlp.googleapis.com \
  --project "$PROJECT_ID" --quiet

# ---- Run Terraform ----------------------------------------------------------
cd terraform
# Initialize Terraform (downloads plugins it needs).
"$TERRAFORM" init -input=false >/dev/null

# Prepare the settings we want to pass to Terraform.
TF_ARGS=(
  -var "project_id=${PROJECT_ID}"
  -var "region=${REGION}"
  -var "prefix=${PREFIX}"
  -var "enable_cloudsql=${ENABLE_CLOUDSQL}"
  -var "retention_days=${RETENTION_DAYS}"
)

# Ask Terraform to show us what it plans to build.
echo "[terraform] planning..."
"$TERRAFORM" plan -input=false "${TF_ARGS[@]}"

# If we only wanted to "plan", we stop here.
if [ "$MODE" = "plan" ]; then
  echo "[terraform] --plan given; stopping before apply."
  exit 0
fi

# Unless we said --yes (-y), ask the user for permission before building.
if [ "$AUTO_APPROVE" != "true" ]; then
  echo
  read -r -p "Create these resources in project ${PROJECT_ID}? [y/N] " ans
  case "$ans" in
    y|Y|yes) ;;
    *) echo "aborted."; exit 0 ;;
  esac
fi

# Actually build the resources in Google Cloud!
echo "[terraform] applying..."
"$TERRAFORM" apply -input=false -auto-approve "${TF_ARGS[@]}"

# ---- Read Terraform Outputs -------------------------------------------------
# Get the names of the resources Terraform just created so we can use them.
BUCKET="$("$TERRAFORM" output -raw bucket_name)"
DATASET="$("$TERRAFORM" output -raw dataset_id)"
SQL_INSTANCE="$("$TERRAFORM" output -raw sql_instance)"
SQL_DB="$("$TERRAFORM" output -raw sql_database)"
cd "$HERE"

# ---- Upload Data to Cloud Storage -------------------------------------------
# Copy all the fake data we generated from our local computer into the Google Cloud Storage bucket.
echo "[upload] copying data to gs://${BUCKET}/ ..."
gsutil -m cp -r data/* "gs://${BUCKET}/"

# ---- Load Data into BigQuery ------------------------------------------------
# BigQuery is Google's super-fast database for analyzing lots of data.
# This helper function loads a CSV file from our storage bucket into a BigQuery table.
bq_load() {
  local table="$1" uri="$2"
  echo "[bigquery] loading ${table} ..."
  # --autodetect: Figure out the columns automatically.
  # --replace: Overwrite any old data in the table.
  bq --location="$REGION" load --quiet --replace --autodetect \
    --source_format=CSV "${PROJECT_ID}:${DATASET}.${table}" "$uri" || \
    echo "  (skipped ${table}: source not present)"
}

# Load the tables if they were enabled.
[ "${ENABLE_CUSTOMERS}" = "true" ] && bq_load customers "gs://${BUCKET}/customers/customers.csv"
[ "${ENABLE_FINANCIAL}" = "true" ] && bq_load financial "gs://${BUCKET}/financial/financial.csv"
[ "${ENABLE_PATENTS}"   = "true" ] && bq_load patents   "gs://${BUCKET}/patents/patents.csv"
if [ "${ENABLE_MEDICAL}" = "true" ]; then
  # Load the medical tables.
  bq_load medical_patients    "gs://${BUCKET}/medical/patients.csv"
  bq_load medical_conditions  "gs://${BUCKET}/medical/conditions.csv"
  bq_load medical_medications "gs://${BUCKET}/medical/medications.csv"
fi

# ---- Load Data into Cloud SQL (Database) ------------------------------------
# If Cloud SQL (Postgres) is enabled, we import the customer SQL file.
if [ "${ENABLE_CLOUDSQL}" = "true" ] && [ "${ENABLE_CUSTOMERS}" = "true" ]; then
  echo "[cloudsql] importing customers into ${SQL_INSTANCE}/${SQL_DB} ..."
  gcloud sql import sql "$SQL_INSTANCE" "gs://${BUCKET}/customers/customers.sql" \
    --database="$SQL_DB" --project="$PROJECT_ID" --quiet
fi

# ---- Done! ------------------------------------------------------------------
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
