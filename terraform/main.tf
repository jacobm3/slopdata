# ============================================================================
# main.tf -- the demo infrastructure SDP / SCC will discover.
#
# Security stance: nothing here is publicly reachable. The bucket enforces
# uniform access + public-access-prevention and grants no public IAM. The
# Cloud SQL instance has a public IP slot but ZERO authorized networks and
# requires SSL, so no network can connect to it; data is loaded server-side
# from the bucket via `gcloud sql import`, not over the wire. We create no new
# firewall rules, service accounts, or public IAM bindings.
# ============================================================================

# Random suffix so globally-unique names (bucket, SQL instance) don't collide.
resource "random_id" "suffix" {
  byte_length = 3
}

# Postgres/BigQuery names can't contain hyphens -- swap them for underscores.
locals {
  name_us = replace(var.prefix, "-", "_")
  suffix  = random_id.suffix.hex
}

# ---------------------------------------------------------------------------
# Cloud Storage: one bucket, sensitive files land in per-type "folders".
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "data" {
  name                        = "${var.prefix}-data-${local.suffix}"
  location                    = var.region
  force_destroy               = true # demo: allow `terraform destroy` to delete contents
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Auto-delete objects so a forgotten demo can't pile up storage cost.
  dynamic "lifecycle_rule" {
    for_each = var.retention_days > 0 ? [1] : []
    content {
      action { type = "Delete" }
      condition { age = var.retention_days }
    }
  }
}

# ---------------------------------------------------------------------------
# BigQuery: one dataset; the bootstrap script loads tables with bq load.
# ---------------------------------------------------------------------------
resource "google_bigquery_dataset" "demo" {
  dataset_id                 = "${local.name_us}_demo"
  location                   = var.region
  delete_contents_on_destroy = true # demo: let destroy remove tables too
  description                = "Synthetic sensitive data for SDP/SCC discovery demo."
}

# ---------------------------------------------------------------------------
# Cloud SQL (Postgres) -- smallest tier, no inbound network access.
# ---------------------------------------------------------------------------
resource "google_sql_database_instance" "main" {
  count            = var.enable_cloudsql ? 1 : 0
  name             = "${var.prefix}-sql-${local.suffix}"
  database_version = "POSTGRES_15"
  region           = var.region

  # demo: allow destroy to delete the instance without manual unlock.
  deletion_protection = false

  settings {
    tier              = "db-f1-micro" # smallest shared-core tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"  # no HA -> cheapest
    disk_type         = "PD_HDD" # cheaper than SSD; fine for a demo
    disk_size         = 10       # GB, the minimum
    disk_autoresize   = false    # don't let it grow and cost more

    backup_configuration {
      enabled = false # demo data is disposable; skip backup cost
    }

    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
      # No authorized_networks -> no client can connect. Data is imported
      # server-side from the bucket, so no connectivity is needed.
    }
  }
}

resource "google_sql_database" "customers" {
  count    = var.enable_cloudsql ? 1 : 0
  name     = "${local.name_us}_customers"
  instance = google_sql_database_instance.main[0].name
}

# Let the Cloud SQL service account READ the bucket so `import` works.
# This is the only IAM binding we create, and it's read-only on our own bucket.
resource "google_storage_bucket_iam_member" "sql_read" {
  count  = var.enable_cloudsql ? 1 : 0
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_sql_database_instance.main[0].service_account_email_address}"
}
