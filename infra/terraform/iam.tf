# BigQuery: run jobs (required for dbt and any BQ query)
resource "google_project_iam_member" "pipeline_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}

# BigQuery: read/write tables in the european_energy dataset
resource "google_bigquery_dataset_iam_member" "pipeline_bq_data_editor" {
  dataset_id = google_bigquery_dataset.european_energy.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline.email}"
}

# GCS: read/write objects in bronze bucket (ingestion writes raw XML + NetCDF)
resource "google_storage_bucket_iam_member" "pipeline_bronze_object_admin" {
  bucket = google_storage_bucket.bronze.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# GCS: read/write objects in silver bucket (Spark writes Parquet, dbt reads)
resource "google_storage_bucket_iam_member" "pipeline_silver_object_admin" {
  bucket = google_storage_bucket.silver.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# GCS: read/write objects in gold bucket (optional analytics mirror)
resource "google_storage_bucket_iam_member" "pipeline_gold_object_admin" {
  bucket = google_storage_bucket.gold.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# Secret Manager: allow pipeline SA to read runtime secrets
resource "google_project_iam_member" "pipeline_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}

# Service Usage: required for API calls from the SA
resource "google_project_iam_member" "pipeline_serviceusage_consumer" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}
