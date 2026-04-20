# European Renewable Energy Analytics Platform

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)
[![Kestra](https://img.shields.io/badge/Kestra-Orchestrated-6E3FF3?style=flat-square)](https://kestra.io/)
[![dbt](https://img.shields.io/badge/dbt-Transformations-FF694B?style=flat-square&logo=dbt&logoColor=white)](https://www.getdbt.com/)
[![BigQuery](https://img.shields.io/badge/BigQuery-Warehouse-4285F4?style=flat-square&logo=googlebigquery&logoColor=white)](https://cloud.google.com/bigquery)
[![GCP](https://img.shields.io/badge/GCP-Cloud-4285F4?style=flat-square&logo=googlecloud&logoColor=white)](https://cloud.google.com/)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-844FBA?style=flat-square&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Looker Studio](https://img.shields.io/badge/Looker_Studio-Dashboard-4285F4?style=flat-square&logo=googleanalytics&logoColor=white)](https://lookerstudio.google.com/)

> "Europe says it's going green. Let's measure it."

Data engineering platform that ingests European electricity grid data (ENTSO-E) and meteorological observations (ERA5), transforms them into a dimensional analytics model, and surfaces actionable energy insights. Supports `DE`, `DK`, `ES`, `FR`, `GR`, `IT`, `PL`, `SE` — run a single country or all at once.

## Table of contents

- [Problem statement and dataset](#problem-statement-and-dataset)
- [Architecture](#architecture)
- [Directory structure](#directory-structure)
- [Fast path](#fast-path)
- [Step-by-step setup](#step-by-step-setup)
  - [Prerequisites](#prerequisites)
  - [Get API keys first](#get-api-keys-first)
  - [Phase 1 — Local setup](#phase-1--local-setup)
  - [Phase 2 — Provision GCP with Terraform](#phase-2--provision-gcp-with-terraform)
  - [Phase 3 — Start Kestra](#phase-3--start-kestra)
  - [Phase 4 — Run the pipeline](#phase-4--run-the-pipeline)
  - [View results in Looker Studio](#view-results-in-looker-studio)
- [Local dev path](#local-dev-path)
- [Verify your setup](#verify-your-setup)
- [Cleanup and destroy](#cleanup-and-destroy)
- [Contributing](#contributing)

---

## Problem statement and dataset

European electricity grid data is publicly available, but it is scattered across APIs, formats, and update cadences that make cross-country comparison difficult.

This project answers questions such as:

- Which countries generate the most renewable energy relative to total output?
- How does wind and solar generation correlate with weather conditions?
- How do generation mixes shift across countries and seasons?
- Which countries are closest to their renewable targets?

To answer those questions reliably, the project builds a repeatable batch pipeline with explicit quality checks, curated warehouse models, and a dashboard backed by stable fact tables instead of ad hoc raw queries.

### Datasets

- [ENTSO-E Transparency Platform](https://transparency.entsoe.eu/) — hourly electricity generation by fuel type (XML), covering `DE`, `DK`, `ES`, `FR`, `GR`, `IT`, `PL`, `SE`
- [ERA5 / Copernicus CDS](https://cds.climate.copernicus.eu/) — daily reanalysis weather observations (NetCDF): wind speed, solar radiation, temperature

---

## Architecture

```
┌──────────── Sources ────────────┐
│  ENTSO-E API (XML, hourly)     │
│  ERA5/CDS (NetCDF, daily)      │
└──────────┬──────────┬───────────┘
           │          │
           ▼          ▼
┌──── Kestra Orchestration ─────┐
│  entsoe_ingest.yaml           │
│  era5_ingest.yaml             │
│  spark_transform.yaml         │
│  daily_pipeline.yaml          │
│  backfill_pipeline.yaml       │
│  dbt_quality.yaml             │
│  dbt_mart.yaml                │
└───────────┬───────────────────┘
            │
    ┌───────┴────────┐
    │  GCS Buckets   │
    │  bronze/silver │
    └───────┬────────┘
            │ external tables
            ▼
    ┌───────────────────────────┐
    │  BigQuery                 │
    │  european_energy dataset  │
    │  raw_ / stg_ / int_ / fct_│
    └───────────┬───────────────┘
            │
            ▼
    ┌──────────────┐
    │ Looker Studio│
    └──────────────┘
```

---

## Directory structure

```
├── docker-compose.yml              # Kestra + PostgreSQL
├── .env                            # API keys and GCP config (not committed)
├── .env.example
├── Makefile
│
├── infra/terraform/                # Terraform — GCP infra
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── apis.tf                     # enables required GCP APIs
│   ├── service_accounts.tf         # pipeline service account
│   ├── iam.tf                      # IAM bindings (GCS + BQ + Secret Manager)
│   ├── secrets.tf                  # Secret Manager slots (empty — populated by Kestra)
│   ├── gcs.tf                      # GCS bucket
│   ├── bigquery.tf                 # BigQuery dataset: european_energy
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── orchestration/
│   ├── config/
│   │   └── countries.json          # country names, ENTSO-E areas, ERA5 bounding boxes
│   ├── flows/                      # Kestra flow YAML definitions
│   │   ├── entsoe_ingest.yaml
│   │   ├── era5_ingest.yaml
│   │   ├── spark_transform.yaml
│   │   ├── daily_pipeline.yaml     # scheduled — runs automatically, do not trigger manually
│   │   ├── backfill_pipeline.yaml  # manual historical replay — use this to populate data
│   │   ├── dbt_quality.yaml
│   │   ├── dbt_mart.yaml
│   │   ├── gcp_kv_setup.yaml       # one-time KV bootstrap (automated by make kestra-bootstrap)
│   │   └── gcp_setup.yaml          # creates GCS bucket + BQ dataset if they don't exist
│   └── scripts/
│       └── tasks/
│           ├── entsoe_fetch.py
│           └── era5_fetch.py
│
├── spark/
│   ├── scripts/
│   │   ├── entsoe_to_parquet.py    # local reference only — production parsing runs in spark_transform.yaml
│   │   └── era5_to_parquet.py      # local helper only — does not stamp a country column
│   └── utils/
│       ├── entsoe_xml_parser.py
│       └── era5_netcdf_helpers.py
│
├── transformations/                # dbt project (BigQuery)
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── models/
│   │   ├── staging/
│   │   ├── intermediate/
│   │   └── mart/
│   ├── seeds/
│   └── tests/
│
├── dashboard/
│   └── queries/                    # Looker Studio SQL recipes
│
├── bronze/                         # Raw data (local mirror before GCS)
└── silver/                         # Clean Parquet (local mirror before GCS)
```

---

## Fast path

If you already have API keys and a GCP project, the full setup is:

```bash
# 1. Clone and install
git clone https://github.com/dimzachar/european-power-observatory.git
cd european-power-observatory
make setup

# 2. Fill in .env (API keys + GCP_PROJECT_ID + GCS_BUCKET)
make env
nano .env

# 3. Provision GCP (creates SA, bucket, BQ dataset)
gcloud auth application-default login
make infra

# 4. Download SA key and generate .env_encoded
make sa-key
make encode-env

# 5. Start Kestra, upload flows, push KV config
make docker-up
make kestra-bootstrap

# 6. Run the pipeline (backfill your date range)
make backfill START=2025-03-01 END=2025-03-07 COUNTRY=GR
```

> [!IMPORTANT]
> ENTSO-E API approval takes 1-3 working days. Request access before anything else — see [Get API keys first](#get-api-keys-first).

---

## Step-by-step setup

### Prerequisites

- Python 3.10+
- `uv` — Python environment manager
- Java 11+ — required only for local PySpark / notebook work
- Docker + Docker Compose
- Google Cloud SDK (`gcloud`)
- Terraform 1.6+

### Get API keys first

**ENTSO-E** (1-3 working days — request this now):
1. Register at https://www.entsoe.eu/
2. Email `transparency@entsoe.eu`, subject: `Restful API access`, include your registration email
3. Once approved: My Account Settings → Generate API Token

**ERA5 / Copernicus CDS** (immediate):
1. Register at https://cds.climate.copernicus.eu/
2. Copy your API token from your profile
3. Accept Terms of Use for the dataset at https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-single-levels (scroll to bottom of the form)

---

### Phase 1 — Local setup

```bash
git clone https://github.com/dimzachar/european-power-observatory.git
cd european-power-observatory
make setup
make env
```

Edit `.env` with the values you have now:

```
ENTSOE_API_KEY=your_api_token_here
CDSAPI_URL=https://cds.climate.copernicus.eu/api
CDSAPI_KEY=your_cds_api_key_here
GCP_PROJECT_ID=your-gcp-project-id
GCP_REGION=europe-west4
GCS_BUCKET=dev-renewable-energy-europe   # must match what Terraform will create (see Phase 2)
COUNTRY=GR
START_DATE=2025-03-01
END_DATE=2025-03-07
```

> [!NOTE]
> Leave `.env_encoded` for now — it requires the service account JSON that Terraform creates in Phase 2.

---

### Phase 2 — Provision GCP with Terraform

Terraform creates everything from scratch: the service account, GCS bucket, BigQuery dataset, and Secret Manager slots. You need zero manually created GCP resources.

**Authenticate:**

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_GCP_PROJECT_ID
```

**Configure tfvars:**

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

<details>
<summary>Windows (PowerShell)</summary>

```powershell
cd infra/terraform
Copy-Item terraform.tfvars.example terraform.tfvars
```
</details>

Edit `terraform.tfvars` — set at minimum:

```hcl
project_id  = "your-gcp-project-id"
environment = "dev"   # bucket name will be: dev-renewable-energy-europe
```

The GCS bucket name is `{environment}-renewable-energy-europe`. Set `GCS_BUCKET` in `.env` to match.

```bash
cd ../..
make infra
```

<details>
<summary>What Terraform creates</summary>

- Required GCP APIs enabled
- Service account `european-energy-pipeline` with GCS, BigQuery, and Secret Manager permissions
- GCS bucket `{environment}-renewable-energy-europe`
- BigQuery dataset `european_energy`
- Secret Manager slots (empty — Kestra reads secrets from `.env_encoded` at runtime)

</details>

**Download the service account key:**

```bash
make sa-key
```

This runs `gcloud iam service-accounts keys create` using the SA email from `terraform output`. The key is saved as `service-account.json` in the repo root.

> [!IMPORTANT]
> `service-account.json` is in `.gitignore`. Never commit it.

**Generate `.env_encoded`:**

```bash
make encode-env
```

This base64-encodes `service-account.json`, `ENTSOE_API_KEY`, and `CDSAPI_KEY` from `.env` into `.env_encoded`, which Kestra reads at startup.

<details>
<summary>If GCS bucket or BigQuery dataset already exist</summary>

Import them into Terraform state instead of letting it create new ones:

```bash
cd infra/terraform
terraform init

# check existing resource names
gcloud storage buckets list --project=YOUR_GCP_PROJECT
gcloud bigquery datasets list --project=YOUR_GCP_PROJECT

# import
terraform import google_storage_bucket.main YOUR_EXISTING_BUCKET
terraform import google_bigquery_dataset.european_energy YOUR_GCP_PROJECT:european_energy

# if a service account already exists
terraform import google_service_account.pipeline projects/YOUR_GCP_PROJECT/serviceAccounts/YOUR_SA_EMAIL

terraform plan   # verify no replacements or deletions before applying
terraform apply
cd ../..
```

</details>

---

### Phase 3 — Start Kestra

```bash
make docker-up
```

Kestra starts at **http://localhost:8080** (login: `admin@kestra.io` / `Admin1234!`).

Once it's up, upload all flows and push KV config in one step:

```bash
make kestra-bootstrap
```

This:
- waits for Kestra to be ready
- uploads all YAML flows from `orchestration/flows/`
- pushes `GCP_PROJECT_ID`, `GCP_LOCATION`, `GCP_BUCKET_NAME`, `GCP_DATASET`, and `CDSAPI_URL` to the Kestra KV store, reading values from your `.env`

> [!NOTE]
> If you ran Terraform, skip `gcp_setup` — the bucket and dataset already exist. `gcp_setup` is only needed if you created GCP resources manually without Terraform. It uses `ifExists: SKIP` so it's safe to run either way, but it's not required.

---

### Phase 4 — Run the pipeline

Use `backfill_pipeline` to populate historical data. `daily_pipeline` runs on a schedule automatically — do not trigger it manually.

**Via make (recommended):**

```bash
# Single country
make backfill START=2025-03-01 END=2025-03-07 COUNTRY=GR

# All countries
make backfill START=2025-03-01 END=2025-03-07 COUNTRY=ALL
```

**Via Kestra UI:**

1. Go to http://localhost:8080 → namespace `european_energy`
2. Open `backfill_pipeline` → Triggers tab → click "Execute backfill"
3. Select your date range and country

The backfill chains all five steps in order:
```
entsoe_ingest → era5_ingest → spark_transform → dbt_quality → dbt_mart
```

To run steps individually instead:

| Flow | What it does |
|------|-------------|
| `entsoe_ingest` | Fetches raw XML → GCS bronze |
| `era5_ingest` | Fetches raw NetCDF → GCS bronze |
| `spark_transform` | XML/NetCDF → Parquet → GCS silver |
| `dbt_quality` | Refreshes raw external tables, builds + tests staging |
| `dbt_mart` | Seeds dimensions, builds + tests intermediate and mart |

---

### View results in Looker Studio

1. Go to https://lookerstudio.google.com/
2. Create new report → data source → BigQuery
3. Connect to `YOUR_GCP_PROJECT.european_energy.fct_renewable_kpi`
4. Use the queries in `dashboard/queries/` as starting points

Dashboard pages:
- Latest generation mix by country and fuel type
- Renewable ranking by share of total generation
- Trends over time (daily/weekly/seasonal)
- Weather correlation (wind speed, solar irradiance, temperature)
- Grid carbon intensity
- Forecast accuracy

---

## Local dev path

For testing individual steps without Kestra:

```bash
# Ingestion
make entsoe-ingest   # reads COUNTRY, START_DATE, END_DATE from .env
make era5-ingest

# dbt
make dbt-run
make test

# Local Spark notebook (requires: uv sync --group notebook)
uv run --group notebook jupyter lab spark/notebooks/renewable_energy_local_spark.ipynb
```

If your local `bronze/` is empty, sync a sample day from GCS first:

```bash
gcloud storage cp "gs://$GCS_BUCKET/bronze/entsoe/GR/generation/2025-03-01/generation.xml" \
  bronze/entsoe/GR/generation/2025-03-01/generation.xml
gcloud storage cp "gs://$GCS_BUCKET/bronze/era5/GR/2025/03/2025-03-01_*.nc" \
  bronze/era5/GR/2025/03/
```

For dbt authentication locally, use one of:
- `export GCP_SERVICE_ACCOUNT_PATH=/absolute/path/to/service-account.json`
- or `gcloud auth application-default login` (ADC, no keyfile needed)

---

## Verify your setup

```bash
# Check Kestra flows are loaded
curl -s http://localhost:8080/api/v1/flows/european_energy | python3 -c "import sys,json; flows=json.load(sys.stdin); [print(f['id']) for f in flows]"

# Warehouse sanity check (run in BigQuery console or bq CLI)
SELECT
  MAX(date_key)      AS latest_date,
  SUM(total_mwh)     AS total_mwh,
  SUM(renewable_mwh) AS renewable_mwh
FROM `YOUR_GCP_PROJECT.european_energy.fct_renewable_kpi`;
```

At this point you should have BigQuery tables populated, and a Looker Studio report that loads data.

---

## Quick commands reference

```bash
make env              # copy .env.example → .env
make setup            # uv sync + dbt deps
make infra            # terraform init + apply
make sa-key           # download SA JSON key (after terraform apply)
make encode-env       # generate .env_encoded from .env + service-account.json
make docker-up        # start Kestra at localhost:8080
make kestra-bootstrap # upload flows + push KV config
make backfill START=2025-03-01 END=2025-03-07 COUNTRY=GR
make docker-down
make clean
```

---

## Cleanup and destroy

```bash
docker compose down
cd infra/terraform && terraform destroy
```

<details>
<summary>What this removes</summary>

- GCS bucket (and all data in it)
- BigQuery dataset `european_energy` and all tables
- Service account `european-energy-pipeline`
- All Secret Manager secrets

</details>

---

## Contributing

Contributions are welcome, especially around data quality, pipeline reliability, testing, and deployment hardening.

<details>
<summary>Before opening a PR</summary>

1. Keep the change focused on one concern
2. Run `uv sync` if dependencies changed
3. Run `dbt deps` and `dbt ls` to verify models load
4. Run `dbt run` and `dbt test` to verify models build and pass tests
5. In the PR description, include the purpose of the change, touched paths, and validation commands you ran

For larger changes, opening an issue first is the best way to align on scope before implementation.
</details>
