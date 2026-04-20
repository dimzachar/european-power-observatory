.PHONY: env encode-env sa-key setup docker-up docker-down infra kestra-bootstrap \
        backfill entsoe-ingest era5-ingest spark-transform dbt-run test clean

# ── Environment ──────────────────────────────────────────────────────────────

env:
	@if [ ! -f .env ]; then cp .env.example .env; echo "Created .env — fill in your API keys and GCP_PROJECT_ID"; else echo ".env already exists"; fi

# Generate .env_encoded from .env + service-account.json
# Requires: .env is filled in, service-account.json exists in repo root
encode-env:
	@test -f service-account.json || (echo "ERROR: service-account.json not found. Run 'make sa-key' first." && exit 1)
	@test -f .env || (echo "ERROR: .env not found. Run 'make env' first." && exit 1)
	@. ./.env && \
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

infra:
	cd infra/terraform && terraform init && terraform apply -auto-approve
	@echo ""
	@echo "Terraform done. Next: make sa-key"

# ── Docker / Kestra ──────────────────────────────────────────────────────────

docker-up:
	docker compose up -d

docker-down:
	docker compose down

# Upload all flows and push KV config to Kestra
# Reads GCP_PROJECT_ID, GCS_BUCKET, GCP_REGION from .env
# Waits for Kestra to be ready before uploading
kestra-bootstrap:
	@test -f .env || (echo "ERROR: .env not found. Run 'make env' first." && exit 1)
	@echo "Waiting for Kestra at http://localhost:8080 ..."
	@until curl -sf -o /dev/null http://localhost:8080/api/v1/flows; do sleep 3; done
	@echo "Kestra is up. Uploading flows..."
	@for f in orchestration/flows/*.yaml; do \
	  echo "  uploading $$f"; \
	  curl -sf -X POST http://localhost:8080/api/v1/flows \
	    -H "Content-Type: application/x-yaml" \
	    --data-binary "@$$f" > /dev/null; \
	done
	@echo "Flows uploaded. Pushing KV config..."
	@. ./.env && \
	  BUCKET=$${GCS_BUCKET:-dev-renewable-energy-europe} && \
	  REGION=$${GCP_REGION:-europe-west4} && \
	  PROJECT=$${GCP_PROJECT_ID} && \
	  for kv in \
	    "GCP_PROJECT_ID=$$PROJECT" \
	    "GCP_LOCATION=$$REGION" \
	    "GCP_BUCKET_NAME=$$BUCKET" \
	    "GCP_DATASET=european_energy" \
	    "CDSAPI_URL=https://cds.climate.copernicus.eu/api"; \
	  do \
	    KEY=$$(echo $$kv | cut -d= -f1); \
	    VAL=$$(echo $$kv | cut -d= -f2-); \
	    curl -sf -X PUT "http://localhost:8080/api/v1/namespaces/european_energy/kv/$$KEY" \
	      -H "Content-Type: application/json" \
	      -d "\"$$VAL\"" > /dev/null && echo "  set $$KEY"; \
	  done
	@echo "Bootstrap complete. Kestra is ready."

# ── Pipeline ─────────────────────────────────────────────────────────────────

# Trigger a backfill run via Kestra API
# Usage: make backfill START=2025-03-01 END=2025-03-07 COUNTRY=ALL
START  ?= 2025-03-01
END    ?= 2025-03-07
COUNTRY ?= GR

backfill:
	@echo "Triggering backfill: $(START) → $(END), country=$(COUNTRY)"
	@curl -sf -X POST "http://localhost:8080/api/v1/executions/european_energy/backfill_pipeline" \
	  -H "Content-Type: application/json" \
	  -d '{"inputs": {"country": "$(COUNTRY)"}}' | python3 -c "import sys,json; e=json.load(sys.stdin); print('Execution ID:', e.get('id','?'))"

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
