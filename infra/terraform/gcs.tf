# Bronze: raw XML + NetCDF
resource "google_storage_bucket" "bronze" {
  name          = "${var.env}-renewable-energy-bronze-${var.project_id}"
  location      = var.location
  force_destroy = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

# Silver: cleaned Parquet
resource "google_storage_bucket" "silver" {
  name          = "${var.env}-renewable-energy-silver-${var.project_id}"
  location      = var.location
  force_destroy = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
}

# Gold: analytics-ready
resource "google_storage_bucket" "gold" {
  name          = "${var.env}-renewable-energy-gold-${var.project_id}"
  location      = var.location
  force_destroy = true
}
