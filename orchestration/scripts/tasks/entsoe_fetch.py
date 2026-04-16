"""Fetch ENTSO-E generation XML locally into bronze storage.

This local helper mirrors the current working Kestra MVP flow:
- documentType A75 (actual generation per type)
- processType A16
- writes one or more local XML files under:
  bronze/entsoe/{country}/generation/{start_date}/

The script is local-first: it fetches XML to the repository's `bronze/`
mirror and does not upload to GCS.
"""

from __future__ import annotations

import os
import sys
import xml.etree.ElementTree as ET
import json
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv()

BASE_URL = "https://web-api.tp.entsoe.eu/api"
OUTPUT_DIR = Path("bronze/entsoe")
COUNTRY_CONFIG_PATH = Path(__file__).resolve().parents[2] / "config" / "countries.json"


def env_first(*names: str, default: str = "") -> str:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return default


def load_country_config() -> dict:
    with COUNTRY_CONFIG_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def fetch_generation(country: str, start_date: str, end_date: str) -> bool:
    api_key = env_first("ENTSOE_API_KEY")
    if not api_key:
        print("[ERROR] ENTSOE_API_KEY not set. Request access via transparency@entsoe.eu")
        return False

    config = load_country_config()
    country_config = config.get(country)
    if country_config is None:
        print(f"[ERROR] No ENTSO-E country configuration for {country}")
        return False

    entsoe_areas = country_config.get("entsoe_areas", [])
    if not entsoe_areas:
        print(f"[ERROR] No ENTSO-E area codes configured for {country}")
        return False

    start = start_date.replace("-", "")
    end = end_date.replace("-", "")

    print(f"[ENTSO-E] Fetching generation for {country} ({start_date} to {end_date})")
    out_dir = OUTPUT_DIR / country / "generation" / start_date
    out_dir.mkdir(parents=True, exist_ok=True)

    failed = False
    for area in entsoe_areas:
        domain = area["code"]
        label = area.get("label", "generation")
        file_name = "generation.xml" if len(entsoe_areas) == 1 and label == "generation" else f"generation_{label}.xml"

        params = {
            "documentType": "A75",
            "processType": "A16",
            "in_Domain": domain,
            "periodStart": f"{start}0000",
            "periodEnd": f"{end}0000",
            "securityToken": api_key,
        }

        try:
            resp = requests.get(BASE_URL, params=params, timeout=120)
        except Exception as exc:
            print(f"[ERROR] Request failed for {country}/{label}: {exc}")
            failed = True
            continue

        is_generation_doc = "<GL_MarketDocument" in resp.text
        is_ack_doc = "<Acknowledgement_MarketDocument" in resp.text

        if resp.status_code == 200 and is_generation_doc and not is_ack_doc:
            out_file = out_dir / file_name
            out_file.write_text(resp.text, encoding="utf-8")
            print(f"[OK] Saved {out_file} ({len(resp.text)} bytes)")
            continue

        print(f"[ERROR] HTTP {resp.status_code} for {country}/{label}")
        print(resp.text[:500])

        try:
            root = ET.fromstring(resp.text)
            reason_code = root.find(".//{*}Reason/{*}code")
            reason_text = root.find(".//{*}Reason/{*}text")
            if reason_code is not None or reason_text is not None:
                print(
                    "ENTSO-E reason:"
                    f" code={reason_code.text if reason_code is not None else 'n/a'}"
                    f" text={reason_text.text if reason_text is not None else 'n/a'}"
                )
        except Exception:
            pass

        failed = True

    return not failed


def main() -> int:
    countries_raw = env_first("COUNTRIES", "COUNTRY", default="GR")
    countries = [country.strip() for country in countries_raw.split(",") if country.strip()]
    start_date = env_first("DATE_START", "START_DATE", default="2025-03-01")
    end_date = env_first("DATE_END", "END_DATE", default="2025-03-02")

    failed = False
    for country in countries:
        print(f"\n{'=' * 60}")
        print(f"ENTSO-E local fetch | country={country} | start={start_date} | end={end_date}")
        print(f"{'=' * 60}\n")
        ok = fetch_generation(country=country, start_date=start_date, end_date=end_date)
        failed = failed or not ok

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
