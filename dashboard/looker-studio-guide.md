# Looker Studio Dashboard Guide

## Setup: Connect to BigQuery

1. Go to [lookerstudio.google.com](https://lookerstudio.google.com)
2. Click **+ Create** → **Data Source** → select **BigQuery**
3. Select your GCP project and dataset: `european_energy`
4. Click **Connect** → **Create Report**

---

## Page 1: Country Performance — "How green is each country?"

### KPI Scorecards
Data source: `fct_renewable_kpi`
- Avg Renewable % → metric: `renewable_pct` (avg)
- Total MWh → metric: `total_mwh` (sum)
- Countries Reporting → metric: `country_code` (count distinct)

### Chart 1: Fossil vs Renewable Split — 100% Stacked Bar
1. Add chart → Bar Chart → set style to **100% stacked**
2. Dimension: `country_name`
3. Metric 1: `renewable_pct` → Avg → label "Renewable %"
4. Metric 2: calculated field `100 - renewable_pct` → label "Fossil + Nuclear %"
5. Style → renewable = green, fossil = grey; sort by `renewable_pct` descending

### Chart 2: Top Energy Sources — Table
1. Add chart → Table
2. Data source: `int_daily_generation`
3. Dimensions: `country_name`, `energy_source`
4. Metrics: `total_mwh` → Sum → "MWh"; `pct_of_total` → Avg → "% of Total"
5. Sort: `total_mwh` descending
6. Style → enable bar visualization on `pct_of_total`; filter `energy_source` regex `.+`

---

## Page 2: Generation Mix — "What fuel mix powered the grid?"

### Data sources
- `int_daily_generation` (date_key, country_name, energy_source, total_mwh, pct_of_total)
- `fct_renewable_kpi` (date_key, country_name, renewable_pct, total_mwh)
- `dim_energy_source` (energy_source, fuel_category, is_renewable, emission_factor_gco2_kwh)

### Chart 1: Fuel Mix by Country — 100% Stacked Bar
1. Add chart → Bar Chart → **100% stacked**
2. Dimension: `country_name`; Breakdown: `energy_source`
3. Metric: `total_mwh` → Sum → "Generation (MWh)"
4. Color palette: wind=blue, solar=yellow, hydro=teal, nuclear=purple, gas=orange, coal=dark grey
5. Add a **Date Range Control** to the page

### Chart 2: Fossil vs Renewable Over Time — Stacked Area
1. Add chart → Area Chart (stacked)
2. Dimension: `date_key` → granularity: **Year Month**
3. Breakdown: `fuel_category` from `dim_energy_source`
   - Or calculated field: `CASE WHEN energy_source IN ('Wind Onshore','Wind Offshore','Solar','Hydro Water Reservoir','Hydro Run-of-river') THEN 'Renewable' ELSE 'Fossil/Nuclear' END`
4. Metric: `total_mwh` → Sum → "Generation (MWh)"
5. Style → renewable = green, fossil = grey; add country filter control

### Chart 3: Country Fuel Comparison — Grouped Bar
1. Add chart → Bar Chart (grouped)
2. Dimension: `country_name`; Breakdown: `energy_source`
3. Metric: `pct_of_total` → Avg → "% of Total"
4. Filter: `energy_source` IN ('Wind Onshore', 'Wind Offshore', 'Solar', 'Fossil Hard coal', 'Fossil Gas', 'Nuclear')
5. Sort: `country_name` alphabetically; show data labels

---

## Page 3: Weather Impact — "Does weather drive renewable output?"

### Data sources
- `int_generation_weather_join` (date_key, country_name, energy_source, actual_mw, avg_wind_speed, avg_solar_radiation_wm2, avg_temp_celsius)
- `fct_renewable_kpi` (date_key, country_name, renewable_pct)

### Chart 1: Wind Speed vs Wind Generation — Scatter
1. Add chart → Scatter Chart; data source: `int_generation_weather_join`
2. Filter: `energy_source` IN ('Wind Onshore', 'Wind Offshore')
3. X-axis: `avg_wind_speed` → Avg; Y-axis: `actual_mw` → Avg
4. Breakdown: `country_name`
5. Style → show trendline (linear), enable tooltips

### Chart 2: Solar Radiation vs Solar Generation — Scatter
1. Add chart → Scatter Chart; data source: `int_generation_weather_join`
2. Filter: `energy_source` = 'Solar'
3. X-axis: `avg_solar_radiation_wm2` → Avg; Y-axis: `actual_mw` → Avg
4. Breakdown: `country_name`; show trendline

### Chart 3: Weather Conditions Over Time — Line (×2)
1. Add chart → Line Chart; data source: `int_generation_weather_join`
2. Dimension: `date_key` → **Year Month**; Breakdown: `country_name`
3. Metric: `avg_wind_speed` → Avg → "Wind Speed (m/s)"; sort `date_key` ascending
4. Duplicate → change metric to `avg_solar_radiation_wm2` → "Solar Radiation (W/m²)"
5. Place side by side; add country filter (multi-select)

### Chart 4: Renewable % vs Wind Speed — Dual-axis Line
1. Add chart → Line Chart; data source: **Blend**
   - Table 1: `fct_renewable_kpi` — dims: `date_key`, `country_code` — metric: `renewable_pct` → Avg
   - Table 2: `int_generation_weather_join` — dims: `date_key`, `country_code` — metric: `avg_wind_speed` → Avg — filter: `energy_source` IN 'Wind Onshore'
   - Join: left outer on `date_key` + `country_code`
2. Dimension: `date_key` → **Year Month**; sort ascending
3. Metric: `renewable_pct` → Avg → "Renewable %" (left axis)
4. Optional metric: `avg_wind_speed` → Avg → "Wind Speed (m/s)" (right axis)

### Chart 5: Country Weather Efficiency — Table
1. Add chart → Table; data source: `int_generation_weather_join`
2. Dimensions: `country_name`, `energy_source`
3. Filter: `energy_source` IN ('Wind Onshore', 'Wind Offshore', 'Solar')
4. Metrics: `avg_wind_speed` → Avg, `avg_solar_radiation_wm2` → Avg, `actual_mw` → Avg
5. Calculated field: `actual_mw / avg_wind_speed` → "MW per m/s"
6. Sort: efficiency field descending; enable bar visualization on efficiency column

---

## Page 4: Carbon Intensity — "What's the real carbon cost of electricity?"

### Data source
`fct_grid_carbon_intensity` (date_key, country_code, country_name, avg_carbon_intensity_gco2_kwh, min_carbon_intensity_gco2_kwh, max_carbon_intensity_gco2_kwh, daily_intensity_range_gco2_kwh, typical_cleanest_hour, avg_renewable_pct)

### Page-level filters (add once, applies to all charts)
- **Date filter**: Add control → Drop-down → field: `date_key` → granularity: Year
- **Country filter**: Add control → Drop-down → field: `country_name` → allow multiple selections

### Chart 1: Carbon Intensity by Country — Horizontal Bar
1. Add chart → Bar Chart (horizontal)
2. Dimension: `country_name`; Metric: `avg_carbon_intensity_gco2_kwh` → Avg
3. Sort: descending (dirtiest at top)
4. Style → single color (dark grey or red); enable data labels

### Chart 2: Carbon Intensity Over Time — Line
1. Add chart → Line Chart
2. Dimension: `date_key` → **Year Month**; Breakdown: `country_name`
3. Metric: `avg_carbon_intensity_gco2_kwh` → Avg → "gCO₂/kWh"
4. Sort: `date_key` ascending

### Chart 3: Cleanest Hour of Day — Table
1. Add chart → Table
2. Dimension: `country_name`
3. Metrics:
   - `avg_carbon_intensity_gco2_kwh` → Avg → "Avg gCO₂/kWh"
   - `typical_cleanest_hour` → Max → "Typical Cleanest Hour"
   - `min_carbon_intensity_gco2_kwh` → Avg → "Best gCO₂/kWh"
   - `daily_intensity_range_gco2_kwh` → Avg → "Daily Range"
4. Sort: `avg_carbon_intensity_gco2_kwh` ascending (cleanest first)
5. Style → bar visualization on avg intensity column (red); alternating row colors

### Chart 4: Carbon Heatmap — Country × Month
1. Add data → BigQuery → **Custom Query** → paste `dashboard/queries/carbon_intensity_heatmap.sql`
   - Replace `YOUR_GCP_PROJECT` with your actual project ID; name it "Carbon Intensity Heatmap"
2. Add chart → Table
3. Dimension 1: `country_name`; Dimension 2: `year_month`
4. Metric: `avg_carbon_intensity_gco2_kwh` → Avg → "gCO₂/kWh"
5. Style → enable **Heatmap** on metric column; sort country alphabetically, year_month ascending

---

## Query Files Reference

| File | Purpose |
|------|---------|
| `dashboard/queries/overview_kpis.sql` | Summary KPI metrics |
| `dashboard/queries/renewable_ranking.sql` | Country ranking by renewable % |
| `dashboard/queries/country_comparison.sql` | Country comparison over time |
| `dashboard/queries/fuel_breakdown.sql` | Generation by fuel type |
| `dashboard/queries/renewable_trends.sql` | 30-day trends |
| `dashboard/queries/weather_correlation.sql` | Weather vs generation |
| `dashboard/queries/carbon_intensity_heatmap.sql` | Carbon heatmap (custom query) |

## Troubleshooting

- No data → check BigQuery tables have recent data
- Slow dashboards → reduce date range or use aggregated tables
- Connection issues → verify service account has BigQuery Viewer role
- Breakdown Dimension disappears → expected when using Optional metrics (dual-axis charts)
