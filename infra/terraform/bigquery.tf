resource "google_bigquery_dataset" "european_energy" {
  dataset_id = "european_energy"
  location   = var.location

  description = "Single BigQuery dataset for the European Energy project, including raw external tables and dbt-prefixed stg/int/fct objects"
}
