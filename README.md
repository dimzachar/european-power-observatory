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
- [Directory Structure](#directory-structure)
- [Quick start](#quick-start)
- [Step-by-step setup](#step-by-step-setup)
  - [Clone the repository](#clone-the-repository)
  - [Install Python dependencies](#install-python-dependencies)
  - [Get API Keys](#get-api-keys)
  - [Set Up Environment Variables](#set-up-environment-variables)
  - [Provision GCP Infrastructure (Terraform)](#provision-gcp-infrastructure-terraform)
  - [Start Kestra](#start-kestra)
  - [Run Ingestion Locally](#run-ingestion-locally)
  - [Run Local PySpark Notebook](#run-local-pyspark-notebook)
  - [Run dbt Models](#run-dbt-models)
  - [Run Everything Through Kestra](#run-everything-through-kestra)
  - [View Results in Looker Studio](#view-results-in-looker-studio)
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

## Directory Structure

```
├── docker-compose.yml              # Kestra + PostgreSQL
├── .env                            # API keys (not committed)
├── .env.example
├── Makefile
│
├── infra/terraform/                # Terraform — GCP infra
│   ├── versions.tf                 # provider version constraints
│   ├── providers.tf
│   ├── variables.tf
│   ├── locals.tf                   # shared labels and resource naming
│   ├── apis.tf                     # enables required GCP APIs
│   ├── service_accounts.tf         # pipeline service account
│   ├── iam.tf                      # IAM bindings (GCS + BQ + Secret Manager)
│   ├── secrets.tf                  # Secret Manager slots
│   ├── gcs.tf                      # GCS bucket
│   ├── bigquery.tf                 # BigQuery dataset: european_energy
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── orchestration/
│   ├── config/
│   │   └── countries.json         # shared country names, ENTSO-E areas, ERA5 bounding boxes
│   ├── flows/                      # Kestra flow YAML definitions
│   │   ├── entsoe_ingest.yaml      # ENTSO-E API → bronze
│   │   ├── era5_ingest.yaml        # ERA5 CDS → bronze
│   │   ├── spark_transform.yaml    # XML/NetCDF → Parquet → silver
│   │   ├── daily_pipeline.yaml     # scheduled single-country or ALL-country end-to-end automation
│   │   ├── backfill_pipeline.yaml  # manual multi-day single-country or ALL-country replay
│   │   ├── dbt_quality.yaml        # refresh raw external tables + build/test staging
│   │   ├── dbt_mart.yaml           # seed + build/test intermediate and mart
│   │   ├── gcp_kv_setup.yaml       # one-time KV store bootstrap
│   │   └── gcp_setup.yaml          # one-time GCP secret/config bootstrap
│   └── scripts/
│       └── tasks/                  # Python scripts called by Kestra
│           ├── entsoe_fetch.py
│           └── era5_fetch.py
│
├── spark/
│   ├── scripts/                    # PySpark transform scripts
│   │   ├── entsoe_to_parquet.py    # XML → structured Parquet (local reference only — timestamp extraction incomplete; production parsing runs inside spark_transform.yaml)
│   │   └── era5_to_parquet.py      # NetCDF → flat tabular Parquet (local helper only — does NOT stamp a `country` column; do not use to manually upload to silver)
│   ├── utils/                      # Shared utilities
│   │   ├── entsoe_xml_parser.py    # IEC 62325 MarketDocument parser
│   │   └── era5_netcdf_helpers.py  # NetCDF reading, coordinate mapping
│   └── requirements.txt            # leftover — not used; uv/pyproject.toml is the setup
│
├── transformations/                # dbt project (BigQuery)
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   ├── models/
│   │   ├── staging/
│   │   │   ├── sources.yml
│   │   │   ├── schema.yml
│   │   │   ├── stg_entsoe__generation.sql
│   │   │   ├── stg_era5__wind.sql
│   │   │   └── stg_era5__solar.sql
│   │   ├── intermediate/
│   │   │   ├── int_daily_generation.sql
│   │   │   ├── int_generation_weather_join.sql
│   │   │   └── int_carbon_intensity.sql
│   │   └── mart/
│   │       ├── fct_renewable_kpi.sql
│   │       ├── fct_grid_carbon_intensity.sql
│   │       └── schema.yml
│   ├── seeds/
│   │   ├── dim_country.csv
│   │   └── dim_energy_source.csv
│   └── tests/
│       ├── assert_country_code_valid.sql
│       ├── assert_minimum_row_coverage.sql
│       └── generic/
│           ├── assert_mw_positive.sql
│           └── assert_timestamp_range.sql
│
├── dashboard/
│   └── queries/                     # Looker Studio SQL recipes
│       ├── overview_kpis.sql
│       ├── renewable_ranking.sql
│       ├── renewable_trends.sql
│       ├── fuel_breakdown.sql
│       ├── country_comparison.sql
│       ├── weather_correlation.sql
│       └── forecast_accuracy.sql
│
├── bronze/                          # Raw data (local mirror before GCS)
└── silver/                          # Clean Parquet (local mirror before GCS)
```

---

## Quick start

1. [Clone the repository](#clone-the-repository) and run `uv sync`
2. Complete [Get API Keys](#get-api-keys) and [Set Up Environment Variables](#set-up-environment-variables)
3. Run `make infra` to provision GCP with Terraform
4. Run `make docker-up` to start Kestra
5. Complete the Kestra bootstrap and execute the pipeline flows
6. [View results in Looker Studio](#view-results-in-looker-studio)

---

## Step-by-step setup

> [!TIP]
> Commands shown use Bash/Linux syntax. PowerShell alternatives are available in collapsibles where the commands differ.

> [!IMPORTANT]
> Required tools:

> - Python 3.10+
> - `uv` for local Python environment management
> - Java 11+ (required for local PySpark / notebook work)
> - Docker + Docker Compose
> - Google Cloud SDK (`gcloud`) configured
> - Terraform 1.6+

### Clone the repository

```bash
git clone https://github.com/dimzachar/european-power-observatory.git
cd european-power-observatory
```

### Install Python dependencies

```bash
uv sync
uv run dbt deps --project-dir transformations
```

If you plan to run the local Spark notebook, also install the notebook extras:

```bash
uv sync --group notebook
```

### Get API Keys

**ENTSO-E** (required for generation data):
1. Register at https://www.entsoe.eu/
2. Email `transparency@entsoe.eu` with subject **"Restful API access"**
3. Include your registration email in the body
4. Wait 1-3 working days for approval
5. Go to **My Account Settings** → click **Generate API Token**
6. Copy the token

**ERA5/Copernicus CDS** (required for weather data):
1. Register at https://cds.climate.copernicus.eu/
2. Go to your profile and copy the API token
3. The token format: `url: https://cds.climate.copernicus.eu/api` + `key: xxxx-xxxx-xxxx`
4. You must also **accept Terms of Use** for the dataset:
   - Go to https://cds.climate.copernicus.eu/cdsapp#!/dataset/reanalysis-era5-single-levels
   - Scroll to bottom of the form → **Agree to Terms of Use**

**GCP Service Account** (for BigQuery + GCS access):
1. Go to https://console.cloud.google.com/iam-admin/serviceaccounts
2. Create a service account for your GCP project
3. Grant roles:
   - **Storage Admin** (for GCS bucket access)
   - **BigQuery Admin** (for dbt table creation)
4. Download the JSON key file
5. Save it somewhere safe (NOT in this repo)

### Set Up Environment Variables

Two env files are used:

- `.env` — for local Python scripts and dbt
- `.env_encoded` — for Kestra (base64-encoded secrets)

```bash
# Copy example env file
cp .env.example .env

# Edit with your actual values
nano .env
```

Fill in `.env`:
```
ENTSOE_API_KEY=your_api_token_here
CDSAPI_URL=https://cds.climate.copernicus.eu/api
CDSAPI_KEY=your_cds_api_key_here
GCP_PROJECT_ID=your-gcp-project-id
GCP_REGION=europe-west4
GCS_BUCKET=your-bronze-bucket-name
COUNTRY=GR
START_DATE=2025-03-01
END_DATE=2025-03-07
```

Then create `.env_encoded` for Kestra (place your GCP service account JSON as `service-account.json` first):

```bash
echo SECRET_GCP_SERVICE_ACCOUNT=$(cat service-account.json | base64 -w 0) > .env_encoded
echo SECRET_ENTSOE_API_KEY=$(echo -n "$ENTSOE_API_KEY" | base64 -w 0) >> .env_encoded
echo SECRET_CDSAPI_KEY=$(echo -n "$CDSAPI_KEY" | base64 -w 0) >> .env_encoded
```

See the [Kestra Google credentials guide](https://kestra.io/docs/how-to-guides/google-credentials#add-service-account-as-a-secret) for details on the service account step.

For local dbt authentication, use one of these:
- export `GCP_SERVICE_ACCOUNT_PATH=/absolute/path/to/service-account.json`
- or set `GOOGLE_APPLICATION_CREDENTIALS` to the same JSON key path
- or run `gcloud auth application-default login` and let dbt use ADC

`uv run dbt ...` does not automatically read `.env`, so export credential variables in your shell before running dbt if you are using a service-account file.

### Provision GCP Infrastructure (Terraform)

> [!IMPORTANT]
> Required tools: `gcloud` CLI and `terraform` (1.6+) must be available in your shell.

**Authenticate with GCP:**

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_GCP_PROJECT
```

**Create your tfvars file:**

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

<details>
<summary>Windows (PowerShell):</summary>

```powershell
cd infra/terraform
Copy-Item terraform.tfvars.example terraform.tfvars
```
</details>

Edit `terraform.tfvars` and set at least `project_id` to your GCP project.

```bash
terraform init
terraform plan
terraform apply
cd ../..
```

<details>
<summary>What this creates:</summary>

- Required GCP APIs enabled (BigQuery, Storage, IAM, Secret Manager)
- Service account `european-energy-pipeline` with permissions to read/write GCS and the BigQuery dataset
- GCS bucket (uses folder prefixes: bronze/, silver/)
- BigQuery dataset: `european_energy`
- Secret Manager slots for runtime secrets (empty — populate manually after apply)

</details>

> [!NOTE]
> After `terraform apply`, populate the Secret Manager slots with your actual API keys via the GCP console or `gcloud`. The service account key for `european-energy-pipeline` is what you'll use as `GCP_SERVICE_ACCOUNT` in Kestra.

---

<details>
<summary>If GCS bucket or BigQuery dataset already exist</summary>

Import them into Terraform state instead of letting it create new ones:

```bash
terraform init

# check your existing resource names first
gcloud storage buckets list --project=YOUR_GCP_PROJECT
gcloud bigquery datasets list --project=YOUR_GCP_PROJECT

# import existing resources
terraform import google_storage_bucket.main YOUR_EXISTING_BUCKET
terraform import google_bigquery_dataset.european_energy YOUR_GCP_PROJECT:european_energy

# if a service account already exists
terraform import google_service_account.pipeline projects/YOUR_GCP_PROJECT/serviceAccounts/YOUR_SA_EMAIL
```

Then update the resource names in `gcs.tf` and `bigquery.tf` to match your existing ones, and run:

```bash
terraform plan
```

> [!IMPORTANT]
> Review the plan before applying. It should show no replacements or deletions — only additions like labels and IAM bindings. If you see a bucket or dataset marked for replacement, fix the name in the `.tf` file first.

```bash
terraform apply
cd ../..
```

Your existing data is untouched. Terraform now manages the resources going forward.
</details>

### Start Kestra

Now that `.env_encoded` is set up, start Kestra:

```bash
docker compose up -d
# or: make docker-up
```

Access the Kestra UI at **http://localhost:8080**  
Login: `admin@kestra.io` / `Admin1234!`

Upload all flows from `orchestration/flows/` via **Flows → Import** in the UI.

Then run these two flows once, in order:

- `gcp_kv_setup` — edit the placeholders in `orchestration/flows/gcp_kv_setup.yaml` first, then execute it. Sets your project ID, bucket name, region, and dataset in the KV store.
- `gcp_setup` — creates the GCS bucket and BigQuery dataset. If you already ran Terraform, it skips creation safely (`ifExists: SKIP`).

### Run Ingestion Locally

Before using Kestra, test locally:

```bash
# Fetch ENTSO-E data for Greece
uv run python orchestration/scripts/tasks/entsoe_fetch.py

# This will fail without ENTSO-E API key — but tests the flow

# Fetch ERA5 weather data for Greece
uv run python orchestration/scripts/tasks/era5_fetch.py
```

To switch countries locally, set `COUNTRY` or `COUNTRIES`. The supported country set and their ENTSO-E / ERA5 configuration live in [`orchestration/config/countries.json`](orchestration/config/countries.json).

Check output in `bronze/`:
```
bronze/
├── entsoe/
│   └── GR/
│       └── generation/
│           └── 2025-03-01/
│               └── generation.xml
└── era5/
    └── GR/
        └── 2025/
            └── 03/
                ├── 2025-03-01_wind.nc
                ├── 2025-03-01_solar.nc
                └── 2025-03-01_temp.nc
```

### Run Local PySpark Notebook

> [!NOTE]
> This step requires the notebook extras. If you skipped them earlier, run `uv sync --group notebook` first.

```bash
uv run --group notebook jupyter lab spark/notebooks/renewable_energy_local_spark.ipynb
```

This notebook mirrors the `06-batch` learning style:
- local `SparkSession`
- ENTSO-E XML parsing
- ERA5 NetCDF flattening
- Spark-side aggregation and join
- local parquet writes to `silver/notebook/`

If you prefer the classic notebook UI instead of JupyterLab:

```bash
uv run --group notebook jupyter notebook spark/notebooks/renewable_energy_local_spark.ipynb
```

If your local `bronze/` directory is empty, sync a sample day from GCS first:

```bash
mkdir -p bronze/entsoe/GR/generation/2025-03-01 bronze/era5/GR/2025/03
gcloud storage cp "gs://$GCS_BUCKET/bronze/entsoe/GR/generation/2025-03-01/generation.xml" bronze/entsoe/GR/generation/2025-03-01/generation.xml
gcloud storage cp "gs://$GCS_BUCKET/bronze/era5/GR/2025/03/2025-03-01_*.nc" bronze/era5/GR/2025/03/
```

### Run dbt Models

The working BigQuery layout uses a single dataset:

- `YOUR_GCP_PROJECT.european_energy.raw_entsoe_generation`
- `YOUR_GCP_PROJECT.european_energy.raw_era5_weather`
- dbt-created `stg_*`, `int_*`, and `fct_*` relations in the same `european_energy` dataset

If you are running dbt manually against newly generated silver Parquet in GCS, refresh the raw external tables first:

```bash
bq --location=EU query --use_legacy_sql=false 'create or replace external table `YOUR_GCP_PROJECT.european_energy.raw_entsoe_generation` options (format="PARQUET", uris=["gs://YOUR_SILVER_BUCKET/silver/entsoe/*"]);'
bq --location=EU query --use_legacy_sql=false 'create or replace external table `YOUR_GCP_PROJECT.european_energy.raw_era5_weather` options (format="PARQUET", uris=["gs://YOUR_SILVER_BUCKET/silver/era5/*"]);'
```

```bash
# Option A: use a service-account JSON key
export GCP_SERVICE_ACCOUNT_PATH="/absolute/path/to/service-account.json"

# Option B: if you already ran `gcloud auth application-default login`,
# dbt can use ADC without exporting a keyfile path

uv run dbt seed --project-dir transformations --profiles-dir transformations
uv run dbt run --project-dir transformations --profiles-dir transformations
uv run dbt test --project-dir transformations --profiles-dir transformations
```

### Run Everything Through Kestra

Once Kestra is running and you have API keys:

1. Navigate to **http://localhost:8080**
2. Browse to **european_energy** namespace
3. Click **Execute** on each flow in order:
   - `entsoe_ingest` → fetches raw XML
   - `era5_ingest` → fetches raw NetCDF
   - `spark_transform` → converts bronze files into silver Parquet in GCS
   - `dbt_quality` → refreshes raw external tables, builds staging views, runs source/staging tests
   - `dbt_mart` → seeds dimensions and builds/tests intermediate + mart objects

Current orchestration note:

> [!NOTE]
> `daily_pipeline` is the scheduled end-to-end flow and accepts a country dropdown — run one country or `ALL` in a single execution. `backfill_pipeline` is the manual replay flow; trigger it from the Kestra UI Schedule trigger to select a date range. Both call `entsoe_ingest`, `era5_ingest`, `spark_transform`, `dbt_quality`, and `dbt_mart` as reusable subflows.

### View Results in Looker Studio

The dashboard shows European renewable energy KPIs:

- **Latest generation mix** — total and renewable energy by country and fuel type (wind, solar, hydro, nuclear, fossil)
- **Renewable ranking** — countries ranked by renewable share of total generation
- **Trends over time** — daily/weekly/seasonal renewable generation patterns
- **Weather correlation** — how wind/solar generation correlates with weather conditions (wind speed, solar irradiance, temperature)
- **Carbon intensity** — grid carbon emissions per unit of electricity generated
- **Forecast accuracy** — historical forecast errors vs actual generation

1. Go to https://lookerstudio.google.com/
2. Create new report → data source → **BigQuery**
3. Connect to `YOUR_GCP_PROJECT.european_energy.fct_renewable_kpi`
4. Build charts using the queries in `dashboard/queries/` as starting points

---

## Quick Commands Reference

```bash
# Sync the local Python environment
uv sync

# Start local dev environment
docker compose up -d
# or: make docker-up

# Run local ingestion
uv run python orchestration/scripts/tasks/entsoe_fetch.py
uv run python orchestration/scripts/tasks/era5_fetch.py

# Open the local Spark notebook (requires: uv sync --group notebook)
uv run --group notebook jupyter lab spark/notebooks/renewable_energy_local_spark.ipynb

# Build dbt models
uv run dbt run --project-dir transformations --profiles-dir transformations

# Test data quality
uv run dbt test --project-dir transformations --profiles-dir transformations

# Clean up
docker compose down
# or: make docker-down
make clean
```

---

## Verify your setup

At this point you should have:

- BigQuery tables under your configured dataset
- a Looker Studio report that loads data successfully
- visible charts for energy KPIs

A quick warehouse sanity query is:

```sql
SELECT
  MAX(date_key)      AS latest_date,
  SUM(total_mwh)     AS total_mwh,
  SUM(renewable_mwh) AS renewable_mwh
FROM `YOUR_GCP_PROJECT.european_energy.fct_renewable_kpi`;
```

Replace `YOUR_GCP_PROJECT` with your real values.

---

## Cleanup and destroy

When you're done, destroy the GCP resources:

```bash
cd infra/terraform
terraform destroy
cd ../..
```

<details>
<summary>What this removes:</summary>

- GCS bucket — unless you set `destroy_bucket_on_destroy = false`
- BigQuery dataset `european_energy` — unless you set `destroy_dataset_on_destroy = false`
- Service account `european-energy-pipeline`
- All Secret Manager secrets

</details>

---

## Contributing

Contributions are welcome, especially around data quality, pipeline reliability, testing, and deployment hardening.


<details>
<summary>Before opening a PR:</summary>

1. Keep the change focused on one concern
2. Run `uv sync` if dependencies changed
3. Run `dbt deps` and `dbt ls` to verify models load
4. Run `dbt run` and `dbt test` to verify models build and pass tests
5. In the PR description, include the purpose of the change, touched paths, and validation commands you ran

For larger changes, opening an issue first is the best way to align on scope before implementation.
</details>

