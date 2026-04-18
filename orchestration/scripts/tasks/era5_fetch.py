"""Fetch ERA5 weather data locally into bronze storage.

This local helper mirrors the current working Kestra MVP flow:
- categories: wind, solar, temp
- one NetCDF file per day/category
- writes to:
  bronze/era5/{country}/{year}/{month}/{date}_{category}.nc
  using country bounding boxes from `orchestration/config/countries.json`

The script is local-first: it writes to the repository's `bronze/` mirror
and does not upload to GCS.
"""

from __future__ import annotations

import os
import sys
import json
from datetime import datetime, timedelta
from pathlib import Path

import time
import cdsapi
from dotenv import load_dotenv

load_dotenv()

OUTPUT_DIR = Path("bronze/era5")
DATASET = "reanalysis-era5-single-levels"
COUNTRY_CONFIG_PATH = Path(__file__).resolve().parents[2] / "config" / "countries.json"

RETRY_ATTEMPTS = 3
RETRY_BACKOFF_BASE = 30  # seconds — CDS queue errors need longer waits: 30, 60, 120


def retrieve_with_retry(client: cdsapi.Client, dataset: str, request: dict, target: str) -> bool:
    """Retrieve from CDS with exponential backoff on transient errors."""
    for attempt in range(1, RETRY_ATTEMPTS + 1):
        try:
            client.retrieve(dataset, request, target)
            return True
        except Exception as exc:
            if attempt == RETRY_ATTEMPTS:
                print(f"[ERROR] CDS retrieve failed after {RETRY_ATTEMPTS} attempts: {exc}")
                return False
            wait = RETRY_BACKOFF_BASE * (2 ** (attempt - 1))
            print(f"[WARN] CDS error (attempt {attempt}/{RETRY_ATTEMPTS}): {exc} — retrying in {wait}s")
            time.sleep(wait)
    return False


CATEGORY_VARIABLES = {
    "wind": [
        "100m_u_component_of_wind",
        "100m_v_component_of_wind",
    ],
    "solar": [
        "surface_solar_radiation_downwards",
    ],
    "temp": [
        "2m_temperature",
    ],
}


def env_first(*names: str, default: str = "") -> str:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return default


def load_country_config() -> dict:
    with COUNTRY_CONFIG_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def daterange(start_date: str, end_date: str):
    start_dt = datetime.strptime(start_date, "%Y-%m-%d")
    end_dt = datetime.strptime(end_date, "%Y-%m-%d")
    current = start_dt
    while current < end_dt:
        yield current
        current += timedelta(days=1)


def build_client() -> cdsapi.Client:
    url = env_first("CDSAPI_URL", default="https://cds.climate.copernicus.eu/api")
    key = env_first("CDSAPI_KEY")
    if key:
        return cdsapi.Client(url=url, key=key)
    return cdsapi.Client(url=url)


def fetch_day(client: cdsapi.Client, country: str, current_dt: datetime) -> bool:
    config = load_country_config()
    country_config = config.get(country)
    area = country_config.get("era5_area") if country_config else None
    if area is None:
        print(f"[ERROR] No ERA5 area configured for country={country}")
        return False

    date_str = current_dt.strftime("%Y-%m-%d")
    year = current_dt.strftime("%Y")
    month = current_dt.strftime("%m")
    day = current_dt.strftime("%d")

    out_dir = OUTPUT_DIR / country / year / month
    out_dir.mkdir(parents=True, exist_ok=True)

    failed = False
    for category, variables in CATEGORY_VARIABLES.items():
        out_file = out_dir / f"{date_str}_{category}.nc"
        if out_file.exists():
            print(f"[SKIP] {out_file}")
            continue

        print(f"[ERA5] Fetching {category} for {country} on {date_str}")
        try:
            ok = retrieve_with_retry(
                client,
                DATASET,
                {
                    "product_type": ["reanalysis"],
                    "variable": variables,
                    "year": year,
                    "month": month,
                    "day": day,
                    "time": [f"{hour:02d}:00" for hour in range(24)],
                    "data_format": "netcdf",
                    "area": area,
                },
                str(out_file),
            )
            if ok:
                print(f"[OK] Saved {out_file}")
            else:
                failed = True
        except Exception as exc:
            print(f"[ERROR] Failed {category} for {date_str}: {exc}")
            failed = True

    return not failed


def main() -> int:
    countries_raw = env_first("COUNTRIES", "COUNTRY", default="GR")
    countries = [country.strip() for country in countries_raw.split(",") if country.strip()]
    start_date = env_first("DATE_START", "START_DATE", default="2025-03-01")
    end_date = env_first("DATE_END", "END_DATE", default="2025-03-02")

    client = build_client()
    failed = False
    for country in countries:
        print(f"\n{'=' * 60}")
        print(f"ERA5 local fetch | country={country} | start={start_date} | end={end_date}")
        print(f"{'=' * 60}\n")
        for current_dt in daterange(start_date, end_date):
            failed = (not fetch_day(client, country, current_dt)) or failed

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
