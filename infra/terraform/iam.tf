# BigQuery: run jobs (required for dbt and any BQ query)
resource "google_project_iam_member" "pipeline_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}

# BigQuery: manage datasets and read/write tables project-wide (required for dbt schemas)
resource "google_project_iam_member" "pipeline_bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}

# GCS: read/write all objects in the single pipeline bucket
resource "google_storage_bucket_iam_member" "pipeline_bucket_object_admin" {
  bucket = google_storage_bucket.main.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# GCS: bucket-level read + update (storage.buckets.get/update) — required by Kestra CreateBucket ifExists check
resource "google_storage_bucket_iam_member" "pipeline_bucket_legacy_reader" {
  bucket = google_storage_bucket.main.name
  role   = "roles/storage.legacyBucketOwner"
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
