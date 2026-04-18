variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "GCP region for regional resources (GCS buckets)."
  type        = string
  default     = "europe-west4"
}

variable "bq_location" {
  description = "BigQuery dataset location."
  type        = string
  default     = "EU"
}

variable "environment" {
  description = "Short environment name used in labels and resource naming."
  type        = string
  default     = "dev"
}

variable "labels" {
  description = "Extra labels to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "secret_ids" {
  description = "Secret Manager secret IDs to create as empty slots for runtime secrets."
  type        = list(string)
  default = [
    "entsoe-api-key",
    "cdsapi-key",
    "gcp-service-account",
  ]
}

variable "gcs_bronze_lifecycle_age_days" {
  description = "Days before incomplete multipart uploads are aborted in the bronze bucket."
  type        = number
  default     = 90
}

variable "gcs_silver_lifecycle_age_days" {
  description = "Days before incomplete multipart uploads are aborted in the silver bucket."
  type        = number
  default     = 90
}

variable "dataset_delete_contents_on_destroy" {
  description = "Allow Terraform destroy to delete tables inside the BigQuery dataset. Keep false for safety."
  type        = bool
  default     = false
}
