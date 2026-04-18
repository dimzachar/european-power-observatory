output "gcs_bronze" {
  description = "GCS bronze bucket URI."
  value       = google_storage_bucket.bronze.url
}

output "gcs_silver" {
  description = "GCS silver bucket URI."
  value       = google_storage_bucket.silver.url
}

output "gcs_gold" {
  description = "GCS gold bucket URI."
  value       = google_storage_bucket.gold.url
}

output "bq_dataset_european_energy" {
  description = "BigQuery dataset ID."
  value       = google_bigquery_dataset.european_energy.dataset_id
}

output "pipeline_service_account_email" {
  description = "Email of the pipeline service account."
  value       = google_service_account.pipeline.email
}

output "secret_ids" {
  description = "Secret Manager secret IDs created for runtime configuration."
  value       = sort([for s in google_secret_manager_secret.runtime : s.secret_id])
}
