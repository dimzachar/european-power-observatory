"""ENTSO-E IEC 62325 MarketDocument XML parser utilities.

ENTSO-E XML structure:
  <Document_MarketDocument>
    <mRID>...</mRID>
    <revisionNumber>1</revisionNumber>
    <TimeSeries>
      <mRID>...</mRID>
      <businessType>...</businessType>
      <psrType>
        <psrType code="B40">Wind</psrType>
      </psrType>
      <Period>
        <timeInterval>
          <start>2025-03-01T00:00Z</start>
          <end>2025-03-02T00:00Z</end>
        </timeInterval>
        <resolution>PT60M</resolution>
        <Point>
          <position>1</position>
          <quantity>1234.5</quantity>
        </Point>
      </Period>
    </TimeSeries>
  </Document_MarketDocument>
"""
from lxml import etree
from datetime import datetime, timedelta
from typing import Optional

NS = {"entsoe": "urn:iec62325.351:tc57wg16:451-3:generationloaddocument:3:0"}

# ENTSO-E PSR type code to human-readable mapping
PSR_TYPE_MAP = {
    "B10": "Fossil Brown coal/Lignite",
    "B11": "Fossil Hard coal",
    "B12": "Fossil Oil shale",
    "B13": "Fossil Oil",
    "B14": "Fossil Natural gas",
    "B15": "Fossil Coal derived gas",
    "B16": "Fossil Lignite",
    "B17": "Fossil Peat",
    "B18": "Fossil Industrial waste",
    "B19": "Fossil Hydrogen",
    "B20": "Fossil Other",
    "B30": "Nuclear",
    "B31": "Solar",
    "B32": "Solar photovoltaic",
    "B33": "Solar concentrated",
    "B34": "Solar thermal",
    "B40": "Wind",
    "B41": "Wind onshore",
    "B42": "Wind offshore",
    "B43": "Tidal",
    "B44": "Marine",
    "B45": "Ocean",
    "B46": "Geothermal",
    "B47": "Biofuel",
    "B48": "Biomass",
    "B49": "Biogas",
    "B50": "Hydro Run-of-river and poundage",
    "B51": "Hydro Water Reservoir",
    "B52": "Hydro Pumped Storage",
    "B53": "Other renewable",
    "B54": "Other non-fossil fuels",
    "B60": "Other",
    "B61": "Waste",
    "B62": "Geothermal",
    "B63": "Other non-fossil fuels",
}

RENEWABLE_SOURCES = {
    "B31", "B32", "B33", "B34",  # Solar
    "B40", "B41", "B42",  # Wind
    "B43", "B44", "B45",  # Tidal/Marine/Ocean
    "B46",  # Geothermal
    "B47", "B48", "B49",  # Biofuels
    "B50", "B51", "B52",  # Hydro
    "B53",  # Other renewable
}


def parse_resolution(resolution_str: str) -> int:
    """Parse ISO 8601 duration to minutes."""
    if "PT60M" in resolution_str or "PT1H" in resolution_str:
        return 60
    elif "PT30M" in resolution_str:
        return 30
    elif "PT15M" in resolution_str:
        return 15
    else:
        return 60  # default to hourly


def resolve_psr_type(code: str) -> str:
    """Convert PSR type code to readable name."""
    return PSR_TYPE_MAP.get(code, f"Unknown ({code})")


def is_renewable(code: str) -> bool:
    """Check if a PSR type code is renewable."""
    return code in RENEWABLE_SOURCES


def parse_xml_timeseries(xml_content: str) -> list[dict]:
    """Parse an ENTSO-E XML document and extract all time series data.

    Returns a list of dicts with:
      - timestamp: datetime
      - psr_type: str (code like B40)
      - psr_name: str (human readable like "Wind")
      - quantity: float (MW)
      - domain: str (actual or forecast)
    """
    tree = etree.fromstring(xml_content.encode()) if isinstance(xml_content, str) else etree.fromstring(xml_content)
    rows = []

    for ts in tree.findall(".//entsoe:TimeSeries", NS):
        # Extract PSR type
        psr_el = ts.find(".//entsoe:psrType/entsoe:psrType", NS)
        psr_code = psr_el.get("code", "unknown") if psr_el is not None else "unknown"
        psr_name = resolve_psr_type(psr_code)

        for period in ts.findall(".//entsoe:Period", NS):
            start_el = period.find(".//entsoe:timeInterval/entsoe:start", NS)
            resolution_el = period.find(".//entsoe:resolution", NS)

            if start_el is None or resolution_el is None:
                continue

            start_dt = datetime.fromisoformat(start_el.text.replace("Z", "+00:00"))
            resolution_min = parse_resolution(resolution_el.text)

            for point in period.findall(".//entsoe:Point", NS):
                position_el = point.find(".//entsoe:position", NS)
                quantity_el = point.find(".//entsoe:quantity", NS)

                if position_el is None or quantity_el is None:
                    continue

                try:
                    position = int(position_el.text)
                    quantity = float(quantity_el.text)
                except (ValueError, TypeError):
                    continue

                ts_val = start_dt + timedelta(minutes=resolution_min * (position - 1))

                rows.append({
                    "timestamp": ts_val,
                    "psr_type": psr_code,
                    "psr_name": psr_name,
                    "quantity": quantity,
                    "is_renewable": is_renewable(psr_code),
                })

    return rows
