resource "google_service_account" "pipeline" {
  depends_on = [google_project_service.required]

  project      = var.project_id
  account_id   = local.pipeline_sa_id
  display_name = "European Energy Pipeline"
  description  = "Runtime identity for Kestra ingestion, Spark transforms, and dbt runs."
}
