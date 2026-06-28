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

cd terraform
terraform destroy -auto-approve \
  -var "project_id=${PROJECT_ID}" \
  -var "region=${REGION}" \
  -var "prefix=${PREFIX}" \
  -var "enable_cloudsql=${ENABLE_CLOUDSQL}" \
  -var "retention_days=${RETENTION_DAYS}"

echo "done. All ${PREFIX} demo resources removed."
