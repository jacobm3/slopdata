#!/usr/bin/env bash
# ============================================================================
# destroy.sh -- delete everything bootstrap.sh created, so you stop paying for
# it. Safe to run repeatedly.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
# shellcheck disable=SC1091
source config.env

if [ -z "${PROJECT_ID:-}" ]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

echo "This will DESTROY all '${PREFIX}' demo resources in project ${PROJECT_ID}."
read -r -p "Type the prefix '${PREFIX}' to confirm: " ans
[ "$ans" = "$PREFIX" ] || { echo "aborted."; exit 0; }

# ---- auth pre-flight check --------------------------------------------------
# Same reasoning as bootstrap.sh: bail early with a clear message if our gcloud
# credentials have expired, since Terraform can't prompt for a login.
if ! gcloud auth print-access-token >/dev/null 2>&1; then
  echo "ERROR: gcloud cannot get a valid access token. Run 'gcloud auth login' and retry."
  exit 1
fi

# ---- give Terraform the SAME credentials gcloud is using --------------------
# On a GCE VM, Terraform's default credentials are the VM's attached service
# account, NOT your gcloud login -- which usually can't delete these resources.
# Mirror the bootstrap.sh fix: hand Terraform an access token minted from your
# active gcloud account, and name a quota project so user-credential APIs (DLP)
# are accepted. See bootstrap.sh for the full explanation.
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
export USER_PROJECT_OVERRIDE="true"
export GOOGLE_BILLING_PROJECT="$PROJECT_ID"

cd terraform
terraform destroy -auto-approve \
  -var "project_id=${PROJECT_ID}" \
  -var "region=${REGION}" \
  -var "prefix=${PREFIX}" \
  -var "enable_cloudsql=${ENABLE_CLOUDSQL}" \
  -var "retention_days=${RETENTION_DAYS}"

echo "done. All ${PREFIX} demo resources removed."
