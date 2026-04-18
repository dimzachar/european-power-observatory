resource "google_bigquery_dataset" "european_energy" {
  depends_on = [google_project_service.required]

  project                    = var.project_id
  dataset_id                 = "european_energy"
  location                   = var.bq_location
  description                = "Single BigQuery dataset for the European Energy project — raw external tables and dbt stg/int/fct models."
  delete_contents_on_destroy = var.dataset_delete_contents_on_destroy
  labels                     = local.common_labels
}
