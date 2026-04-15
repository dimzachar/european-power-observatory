output "gcs_bronze" {
  description = "GCS bronze bucket URI"
  value       = google_storage_bucket.bronze.url
}

output "gcs_silver" {
  description = "GCS silver bucket URI"
  value       = google_storage_bucket.silver.url
}

output "gcs_gold" {
  description = "GCS gold bucket URI"
  value       = google_storage_bucket.gold.url
}

output "bq_dataset_european_energy" {
  description = "BigQuery dataset ID for the European Energy warehouse"
  value       = google_bigquery_dataset.european_energy.dataset_id
}
