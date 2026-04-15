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

    # Get dimensions
    times = ds.coords["time"].values if "time" in ds.coords else ds.coords["valid_time"].values
    lats = ds.coords["latitude"].values if "latitude" in ds.coords else ds.coords["lat"].values
    lons = ds.coords["longitude"].values if "longitude" in ds.coords else ds.coords["lon"].values

    # Flatten: for each variable, create rows of (time, lat, lon, value)
    rows = []
    for var_name in ds.data_vars:
        var_data = ds[var_name]
        # Expected shape: (time, lat, lon)
        if var_data.ndim == 3:
            for t_idx, t in enumerate(times):
                for lat_idx, lat in enumerate(lats):
                    for lon_idx, lon in enumerate(lons):
                        value = var_data[t_idx, lat_idx, lon_idx].item()
                        if not np.isnan(value):
                            rows.append({
                                "timestamp": pd.Timestamp(t),
                                "lat": float(lat),
                                "lon": float(lon),
                                "variable": var_name,
                                "value": float(value),
                            })

    ds.close()
    return pd.DataFrame(rows)


def main():
    """Convert all ERA5 NetCDF files to Parquet."""
    print("Starting ERA5 NetCDF → Parquet transformation...")

    for nc_file in RAW_DIR.glob("**/*.nc"):
        print(f"  Processing: {nc_file}")

        # Parse date from filename: {date}_{category}.nc
        parts = nc_file.stem.split("_")
        date_str = parts[0]
        cat = "_".join(parts[1:])

        out_path = OUT_DIR / cat / nc_file.stem + ".parquet"
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
