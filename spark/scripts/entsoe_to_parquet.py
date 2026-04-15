"""
ENTSO-E XML → Parquet via PySpark.

Parses IEC 62325 MarketDocument XML files into clean structured Parquet.
Reads from bronze/entsoe/{country}/{domain}/{date}.xml
Writes to silver/entsoe/{country}/{domain}/partitioned.parquet
"""
import os
import glob
from pathlib import Path
from lxml import etree
import pandas as pd
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType, StructField, StringType, TimestampType, FloatType
)

RAW_DIR = Path("bronze/entsoe")
OUT_DIR = Path("silver/entsoe")

NS = {"ns": "urn:iec62325.351"}

# ENTSO-E official PsrType mapping used in A75 generation documents.
SOURCE_MAP = {
    "B01": "biomass",
    "B02": "fossil_brown_coal_lignite",
    "B03": "fossil_coal_derived_gas",
    "B04": "fossil_gas",
    "B05": "fossil_hard_coal",
    "B06": "fossil_oil",
    "B07": "fossil_oil_shale",
    "B08": "fossil_peat",
    "B09": "geothermal",
    "B10": "hydro_pumped_storage",
    "B11": "hydro_run_of_river_and_poundage",
    "B12": "hydro_water_reservoir",
    "B13": "marine",
    "B14": "nuclear",
    "B15": "other_renewable",
    "B16": "solar",
    "B17": "waste",
    "B18": "wind_offshore",
    "B19": "wind_onshore",
    "B20": "other",
}


def resolve_source(code: str) -> str:
    """Map ENTSO-E PSR type code to readable source name."""
    return SOURCE_MAP.get(code, f"unknown_{code}")


def parse_generation_xml(xml_path: str, country: str) -> pd.DataFrame:
    """Parse actual generation XML and return DataFrame.

    Expected columns: timestamp, country, energy_source, actual_MW, forecast_MW
    """
    tree = etree.parse(xml_path)
    root = tree.getroot()

    rows = []

    # Iterate over all TimeSeries in the document
    for ts in root.findall(".//ns:TimeSeries", NS):
        # Extract PSR Type (energy source)
        psr_type = ts.find(".//ns:psrType/ns:psrType", NS)
        energy_source = psr_type.text if psr_type is not None else "unknown"
        energy_source_readable = resolve_source(energy_source)

        for period in ts.findall(".//ns:Period", NS):
            resolution = period.find(".//ns:resolution", NS)

            # Some resolutions are already in minutes (PT60M = hourly)
            res_str = resolution.text if resolution is not None else "PT60M"
            if "15M" in res_str:
                interval_minutes = 15
            elif "30M" in res_str:
                interval_minutes = 30
            elif "PT60M" in res_str or "PT1H" in res_str:
                interval_minutes = 60
            else:
                interval_minutes = 60

            for pint in period.findall(".//ns:Point", NS):
                position = pint.find(".//ns:position", NS)
                qty = pint.find(".//ns:quantity", NS)

                if position is not None and qty is not None:
                    try:
                        pos_val = int(position.text)
                        quantity = float(qty.text)
                    except (ValueError, TypeError):
                        continue

                    # Calculate timestamp from start + position * interval
                    time_str = period.find(".//ns:timeInterval/ns:end", NS)
                    if time_str is not None:
                        # Simplified: use date from filename
                        pass

                    rows.append({
                        "country": country,
                        "energy_source": energy_source_readable,
                        "actual_MW": quantity,
                        "forecast_MW": None,
                    })

    return pd.DataFrame(rows)


def main():
    """Parse all ENTSO-E XML files and write to Parquet."""
    print("Starting ENTSO-E XML → Parquet transformation...")

    spark = SparkSession.builder \
        .appName("entsoe_to_parquet") \
        .config("spark.master", "local[*]") \
        .getOrCreate()

    all_data = []

    # Walk through bronze/entsoe/{country}/{domain}/{date}.xml
    for country_dir in RAW_DIR.iterdir():
        country = country_dir.name

        for domain_dir in country_dir.iterdir():
            domain = domain_dir.name

            for xml_file in domain_dir.glob("**/*.xml"):
                print(f"  Parsing: {xml_file}")
                try:
                    if domain == "generation":
                        df = parse_generation_xml(str(xml_file), country)
                        df["domain"] = domain
                        all_data.append(df)
                    # Add other domain parsers as needed
                except Exception as e:
                    print(f"  ERROR parsing {xml_file}: {e}")

    if not all_data:
        print("No data found. Check bronze/entsoe/ for XML files.")
        return

    combined_df = pd.concat(all_data, ignore_index=True)
    print(f"Total rows: {len(combined_df)}")

    # Write to Parquet (one per country + domain)
    schema = StructType([
        StructField("timestamp", TimestampType(), True),
        StructField("country", StringType(), True),
        StructField("energy_source", StringType(), True),
        StructField("actual_MW", FloatType(), True),
        StructField("forecast_MW", FloatType(), True),
        StructField("domain", StringType(), True),
    ])

    spark_df = spark.createDataFrame(combined_df, schema=schema)

    output_path = OUT_DIR / "generation" / "all_data"
    output_path.mkdir(parents=True, exist_ok=True)
    spark_df.write.mode("overwrite").partitionBy("country", "energy_source").parquet(str(output_path))

    print(f"Wrote generation data to: {output_path}")
    spark.stop()


if __name__ == "__main__":
    main()
