"""ERA5 NetCDF reading and coordinate mapping utilities."""
import xarray as xr
import numpy as np
import pandas as pd
from pathlib import Path
from typing import Tuple


# Greece bounding box (approximate)
GREECE_BBOX = {
    "lat_min": 34.5,
    "lat_max": 41.5,
    "lon_min": 19.0,
    "lon_max": 29.5,
}

# ERA5 variable names to human-readable
VAR_MAP = {
    "100m_u-component_of_wind": "wind_100m_u",
    "100m_v-component_of_wind": "wind_100m_v",
    "10m_u-component_of_wind": "wind_10m_u",
    "10m_v-component_of_wind": "wind_10m_v",
    "2m_temperature": "t2m",
    "2m_dewpoint_temperature": "d2m",
    "surface_solar_radiation_downwards": "ssrd",
    "surface_thermal_radiation_downwards": "strd",
    "total_cloud_cover": "tcc",
    "total_precipitation": "tp",
}


def open_netcdf(nc_path: Path) -> xr.Dataset:
    """Open a NetCDF file and return the dataset."""
    return xr.open_dataset(nc_path)


def netcdf_to_dataframe(nc_path: Path) -> pd.DataFrame:
    """Convert a NetCDF to a flat DataFrame with named columns."""
    ds = xr.open_dataset(nc_path)

    # Rename variables to short names
    ds = ds.rename({k: VAR_MAP.get(k, k) for k in ds.data_vars})

    df = ds.to_dataframe().reset_index()

    # Rename standard ERA5 coordinates
    if "valid_time" in df.columns:
        df = df.rename(columns={"valid_time": "time"})
    if "latitude" in df.columns:
        df = df.rename(columns={"latitude": "lat"})
    if "longitude" in df.columns:
        df = df.rename(columns={"longitude": "lon"})

    # Convert temperature from K to C
    for temp_col in ["t2m", "d2m"]:
        if temp_col in df.columns:
            df[temp_col] = df[temp_col] - 273.15

    # Convert precipitation from m to mm
    if "tp" in df.columns:
        df["tp"] = df["tp"] * 1000

    # Convert cloud cover from fraction (0-1) to percentage (0-100)
    if "tcc" in df.columns:
        df["tcc"] = df["tcc"] * 100

    ds.close()
    return df


def wind_speed_from_uv(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Compute wind speed from u and v components."""
    return np.sqrt(u**2 + v**2)


def wind_direction_from_uv(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Compute wind direction in degrees from u and v components."""
    return np.arctan2(v, u) * 180 / np.pi % 360


def aggregate_to_country(df: pd.DataFrame, bbox: dict = GREECE_BBOX) -> pd.DataFrame:
    """Aggregate grid-cell level weather data to country-level averages.

    Groups by timestamp and computes mean across all grid cells in bbox.
    """
    # Filter to bounding box
    filtered = df[
        (df["lat"] >= bbox["lat_min"]) &
        (df["lat"] <= bbox["lat_max"]) &
        (df["lon"] >= bbox["lon_min"]) &
        (df["lon"] <= bbox["lon_max"])
    ]

    # Group by timestamp and average across grid cells
    numeric_cols = filtered.select_dtypes(include=[np.number]).columns
    result = filtered.groupby("time")[numeric_cols].mean().reset_index()

    return result
