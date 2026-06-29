# These outputs are consumed by bootstrap.sh to upload data and load the DB.

output "bucket_name" {
  value       = google_storage_bucket.data.name
  description = "GCS bucket holding all generated data."
}

output "dataset_id" {
  value       = google_bigquery_dataset.demo.dataset_id
  description = "BigQuery dataset for loaded tables."
}

output "sql_instance" {
  value       = var.enable_cloudsql ? google_sql_database_instance.main[0].name : ""
  description = "Cloud SQL instance name (empty if DB disabled)."
}

output "sql_connection_name" {
  value       = var.enable_cloudsql ? google_sql_database_instance.main[0].connection_name : ""
  description = "Cloud SQL connection name."
}

output "sql_database" {
  value       = var.enable_cloudsql ? google_sql_database.customers[0].name : ""
  description = "Cloud SQL database name."
}

output "sdp_secret_id" {
  value       = join("", google_secret_manager_secret.sdp_sql_password[*].id)
  description = "The Secret Manager secret ID storing the SDP read-only SQL password."
}

output "sdp_instructions" {
  value       = <<EOF
%{ if var.enable_cloudsql ~}
To scan the Cloud SQL instance with Sensitive Data Protection (SDP):
1. Go to the SDP Console: https://console.cloud.google.com/security/dlp
2. Navigate to "Configuration" -> "Connections" (or "Discovery" depending on UI).
3. Create or edit a connection for this Cloud SQL instance:
   - Instance: ${join("", google_sql_database_instance.main[*].connection_name)}
   - Database: ${join("", google_sql_database.customers[*].name)}
   - Username: sdp_readonly
   - Password: Use the Secret Manager secret:
     ${join("", google_secret_manager_secret.sdp_sql_password[*].id)}
4. Ensure the SDP Service Agent has access to the secret (this Terraform configuration has already granted 'roles/secretmanager.secretAccessor' to service-${data.google_project.project.number}@gcp-sa-dlp.iam.gserviceaccount.com).
%{ else ~}
Cloud SQL is disabled; no SDP configuration needed.
%{ endif ~}
EOF
  description = "Instructions for configuring SDP to scan the Cloud SQL instance."
}
