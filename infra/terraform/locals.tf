locals {
  resource_prefix = "european-energy"

  common_labels = merge(
    {
      app         = local.resource_prefix
      environment = var.environment
      managed_by  = "terraform"
    },
    var.labels
  )

  required_apis = toset([
    "bigquery.googleapis.com",
    "bigquerystorage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])

  pipeline_sa_id = "european-energy-pipeline"
}
