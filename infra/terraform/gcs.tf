resource "google_storage_bucket" "main" {
  depends_on = [google_project_service.required]

  name          = "${var.environment}-renewable-energy-europe"
  project       = var.project_id
  location      = var.location
  force_destroy = true
  labels        = local.common_labels

  lifecycle_rule {
    condition {
      age = var.gcs_lifecycle_age_days
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}
