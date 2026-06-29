#!/usr/bin/env bash

# ============================================================================
# Welcome to destroy.sh!
# This script is like an "eraser" or a "cleanup crew".
# Its job is to delete all the Google Cloud toys (resources) we built
# using the bootstrap.sh script, so Google doesn't charge us money for them.
# ============================================================================

# These are safety rules for the computer.
# -e: Stop immediately if any command fails (makes a mistake).
# -u: Stop if we try to use a variable (a box of information) that hasn't been defined yet.
# -o pipefail: If we chain commands together, stop if any part of the chain fails.
set -euo pipefail

# This line finds out exactly where this script file is living on your computer.
# It's like finding your home address so you don't get lost.
HERE="$(cd "$(dirname "$0")" && pwd)"

# Now we move the computer's attention (current directory) to that home folder.
cd "$HERE"

# This line is like opening a recipe book called "config.env" and loading all the
# ingredients (settings) we need, like our project name and region.
# shellcheck disable=SC1091
source config.env

# We need to know which Google Cloud project we are working in.
# If the "config.env" file didn't tell us (it's empty), we ask Google Cloud's helper tool
# (gcloud) to tell us which project is currently active.
if [ -z "${PROJECT_ID:-}" ]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

# This is a warning message. It tells the user: "Hey, we are about to delete everything!"
echo "This will DESTROY all '${PREFIX}' demo resources in project ${PROJECT_ID}."

# We ask the user to type the prefix (the special name tag) to confirm they really want to do this.
# It's like a safety lock on a toy.
read -r -p "Type the prefix '${PREFIX}' to confirm: " ans

# If what they typed does NOT match the prefix, we stop (abort) and do nothing.
# Safety first!
[ "$ans" = "$PREFIX" ] || { echo "aborted."; exit 0; }

# Now we go into the "terraform" folder. Terraform is our robot builder.
cd terraform

# We tell the Terraform robot to "destroy" (delete) everything.
# We also pass in the settings (variables) so it knows exactly what to delete.
# -auto-approve means "don't ask me again, just do it".
terraform destroy -auto-approve \
  -var "project_id=${PROJECT_ID}" \
  -var "region=${REGION}" \
  -var "prefix=${PREFIX}" \
  -var "enable_cloudsql=${ENABLE_CLOUDSQL}" \
  -var "retention_days=${RETENTION_DAYS}"

# Finally, we tell the user we are done!
echo "done. All ${PREFIX} demo resources removed."
