resource "google_storage_bucket" "bronze" {
  depends_on = [google_project_service.required]

  name          = "${var.environment}-renewable-energy-bronze-${var.project_id}"
  project       = var.project_id
  location      = var.location
  force_destroy = true
  labels        = local.common_labels

  lifecycle_rule {
    condition {
      age = var.gcs_bronze_lifecycle_age_days
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

resource "google_storage_bucket" "silver" {
  depends_on = [google_project_service.required]

  name          = "${var.environment}-renewable-energy-silver-${var.project_id}"
  project       = var.project_id
  location      = var.location
  force_destroy = true
  labels        = local.common_labels

  lifecycle_rule {
    condition {
      age = var.gcs_silver_lifecycle_age_days
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

resource "google_storage_bucket" "gold" {
  depends_on = [google_project_service.required]

  name          = "${var.environment}-renewable-energy-gold-${var.project_id}"
  project       = var.project_id
  location      = var.location
  force_destroy = true
  labels        = local.common_labels
}
