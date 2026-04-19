.PHONY: setup docker-up docker-down infra entsoe-ingest era5-ingest spark-transform dbt-run test clean

setup:
	@echo "Installing Python dependencies..."
	uv sync
	uv run dbt deps --project-dir transformations --profiles-dir transformations

docker-up:
	docker compose up -d

docker-down:
	docker compose down

infra:
	cd infra/terraform && terraform init && terraform apply -auto-approve

entsoe-ingest:
	@echo "Running ENTSO-E ingestion for $(COUNTRY) ($(START_DATE) to $(END_DATE))..."
	uv run python orchestration/scripts/tasks/entsoe_fetch.py

era5-ingest:
	@echo "Running ERA5 ingestion for $(COUNTRY) ($(START_DATE) to $(END_DATE))..."
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

clean:
	rm -rf bronze/*
	rm -rf silver/*
	find transformations/target -maxdepth 1 -not -name target -exec rm -rf {} +
