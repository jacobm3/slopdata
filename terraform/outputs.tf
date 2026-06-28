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
