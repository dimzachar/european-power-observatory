"""ERA5 NetCDF → flat Parquet.

Reads NetCDF files from bronze/era5/{year}/{month}/{date}_{cat}.nc
Writes to silver/era5/{cat}/partitioned.parquet

For each grid cell in the Greek bounding box.
"""
import os
import glob
from pathlib import Path
import pandas as pd
from datetime import datetime
import xarray as xr
import numpy as np

RAW_DIR = Path("bronze/era5")
OUT_DIR = Path("silver/era5")


def netcdf_to_df(nc_path: Path) -> pd.DataFrame:
    """Convert a single NetCDF to flat DataFrame with lat/lon/timestamp columns."""
    ds = xr.open_dataset(nc_path)

    # Flatten: vectorized via xarray → DataFrame (avoids pure-Python triple loop)
    frames = []
    for var_name in ds.data_vars:
        var_data = ds[var_name]
        if var_data.ndim == 3:
            df = var_data.to_dataframe(name="value").reset_index()
            df["variable"] = var_name
            frames.append(df)

    ds.close()
    if not frames:
        return pd.DataFrame()

    combined = pd.concat(frames, ignore_index=True)
    # Normalise coordinate column names (ERA5 uses latitude/longitude or lat/lon)
    combined = combined.rename(columns={
        "valid_time": "time",
        "latitude": "lat",
        "longitude": "lon",
    })
    combined = combined.rename(columns={"time": "timestamp"})
    combined["timestamp"] = pd.to_datetime(combined["timestamp"])
    combined = combined.dropna(subset=["value"])
    return combined[["timestamp", "lat", "lon", "variable", "value"]]


def main():
    """Convert all ERA5 NetCDF files to Parquet."""
    print("Starting ERA5 NetCDF → Parquet transformation...")

    for nc_file in RAW_DIR.glob("**/*.nc"):
        print(f"  Processing: {nc_file}")

        # Parse date from filename: {date}_{category}.nc
        parts = nc_file.stem.split("_")
        date_str = parts[0]
        cat = "_".join(parts[1:])

        out_path = OUT_DIR / cat / (nc_file.stem + ".parquet")
        if out_path.exists():
            print(f"    [SKIP] already exists: {out_path}")
            continue

        df = netcdf_to_df(nc_file)
        print(f"    Rows: {len(df)}")

        # Write to Parquet
        (OUT_DIR / cat).mkdir(parents=True, exist_ok=True)
        df.to_parquet(out_path, index=False)
        print(f"    Saved: {out_path}")

    print("\nDone.")


if __name__ == "__main__":
    main()
