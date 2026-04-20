.PHONY: env gcp-auth encode-env sa-key setup docker-up docker-down infra \
        entsoe-ingest era5-ingest spark-transform dbt-run test clean

# ── Environment ──────────────────────────────────────────────────────────────

env:
	@if [ ! -f .env ]; then cp .env.example .env; echo "Created .env — fill in your API keys and GCP_PROJECT_ID"; else echo ".env already exists"; fi

# Authenticate gcloud CLI and ADC using the project ID from .env
gcp-auth:
	@test -f .env || (echo "ERROR: .env not found. Run 'make env' first." && exit 1)
	@PROJECT_ID=$$(grep '^GCP_PROJECT_ID=' .env | cut -d= -f2 | tr -d '[:space:]'); \
	if [ -z "$$PROJECT_ID" ] || [ "$$PROJECT_ID" = "your-gcp-project-id" ]; then \
	  echo "ERROR: Please set a valid GCP_PROJECT_ID in .env first."; \
	  exit 1; \
	fi; \
	echo "Authenticating gcloud for project $$PROJECT_ID..."; \
	gcloud auth login && \
	gcloud config set project $$PROJECT_ID && \
	gcloud auth application-default login && \
	gcloud auth application-default set-quota-project $$PROJECT_ID

# Generate .env_encoded from .env + service-account.json
# Requires: .env is filled in, service-account.json exists in repo root
encode-env:
	@test -f service-account.json || (echo "ERROR: service-account.json not found. Run 'make sa-key' first." && exit 1)
	@test -f .env || (echo "ERROR: .env not found. Run 'make env' first." && exit 1)
	@eval "$$(tr -d '\r' < .env)" && \
	  printf "SECRET_GCP_SERVICE_ACCOUNT=%s\n" "$$(cat service-account.json | base64 -w 0)" > .env_encoded && \
	  printf "SECRET_ENTSOE_API_KEY=%s\n" "$$(printf '%s' "$$ENTSOE_API_KEY" | base64 -w 0)" >> .env_encoded && \
	  printf "SECRET_CDSAPI_KEY=%s\n" "$$(printf '%s' "$$CDSAPI_KEY" | base64 -w 0)" >> .env_encoded
	@echo "Created .env_encoded"

# Download SA key for the service account Terraform created
# Requires: terraform apply has been run, gcloud is authenticated
sa-key:
	@SA_EMAIL=$$(cd infra/terraform && terraform output -raw pipeline_service_account_email) && \
	  echo "Downloading key for $$SA_EMAIL ..." && \
	  gcloud iam service-accounts keys create service-account.json --iam-account=$$SA_EMAIL
	@echo "Saved service-account.json — run 'make encode-env' next"

# ── Dependencies ─────────────────────────────────────────────────────────────

setup:
	uv sync
	uv run dbt deps --project-dir transformations --profiles-dir transformations

# ── Infrastructure ───────────────────────────────────────────────────────────
# Derives terraform environment from GCS_BUCKET in .env.
# GCS_BUCKET must follow the pattern <env>-renewable-energy-europe
# e.g. dev-renewable-energy-europe  → environment=dev
#      prod-renewable-energy-europe → environment=prod
infra:
	@test -f .env || (echo "ERROR: .env not found. Run 'make env' first." && exit 1)
	@PROJECT_ID=$$(grep '^GCP_PROJECT_ID=' .env | cut -d= -f2 | tr -d '[:space:]'); \
	  REGION=$$(grep '^GCP_REGION=' .env | cut -d= -f2 | tr -d '[:space:]'); \
	  BUCKET=$$(grep '^GCS_BUCKET=' .env | cut -d= -f2 | tr -d '[:space:]'); \
	  ENV=$$(echo "$$BUCKET" | sed 's/-renewable-energy-europe$$//'); \
	  if [ -z "$$ENV" ] || [ "$$ENV" = "$$BUCKET" ]; then \
	    echo "ERROR: GCS_BUCKET='$$BUCKET' is missing an environment prefix."; \
	    echo "       Expected pattern : <env>-renewable-energy-europe"; \
	    echo "       Examples         : dev-renewable-energy-europe"; \
	    echo "                        : prod-renewable-energy-europe"; \
	    echo "       Fix .env and re-run make infra."; \
	    exit 1; \
	  fi; \
	  echo "Derived environment=$$ENV from GCS_BUCKET=$$BUCKET (Terraform will create bucket: $$BUCKET)"; \
	  if [ ! -f infra/terraform/terraform.tfvars ]; then \
	    cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars; \
	    sed -i "s|your-gcp-project-id|$$PROJECT_ID|" infra/terraform/terraform.tfvars; \
	    sed -i "s|europe-west4|$$REGION|g" infra/terraform/terraform.tfvars; \
	    sed -i "s|owner = \"your-name\"|owner = \"pipeline\"|" infra/terraform/terraform.tfvars; \
	    echo "Generated infra/terraform/terraform.tfvars (project_id=$$PROJECT_ID, location=$$REGION, environment=$$ENV)"; \
	  else \
	    echo "infra/terraform/terraform.tfvars already exists — using as-is"; \
	  fi; \
	  cd infra/terraform && terraform init && terraform apply -auto-approve -var="environment=$$ENV"
	@echo ""
	@echo "Terraform done. Next: make sa-key"


# ── Docker / Kestra ──────────────────────────────────────────────────────────

docker-up:
	docker compose up -d

docker-down:
	docker compose down

# ── Local dev ────────────────────────────────────────────────────────────────

entsoe-ingest:
	uv run python orchestration/scripts/tasks/entsoe_fetch.py

era5-ingest:
	uv run python orchestration/scripts/tasks/era5_fetch.py

spark-transform:
	spark-submit \
		--packages com.google.cloud:google-cloud-storage:2.27.0 \
		--conf spark.hadoop.google.cloud.auth.service.account.enable=true \
		spark/scripts/entsoe_to_parquet.py

dbt-run:
	uv run dbt run --project-dir transformations --profiles-dir transformations

test:
	uv run dbt test --project-dir transformations --profiles-dir transformations

# ── Cleanup ──────────────────────────────────────────────────────────────────

clean:
	rm -rf bronze/* silver/*
	find transformations/target -maxdepth 1 -not -name target -exec rm -rf {} +
