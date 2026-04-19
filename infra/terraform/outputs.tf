output "gcs_bucket" {
  description = "GCS bucket URI (bronze/ and silver/ are path prefixes within this bucket)."
  value       = google_storage_bucket.main.url
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
