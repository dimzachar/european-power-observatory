-- Carbon intensity heatmap: country × month, value = avg gCO2/kWh
-- Use as a custom query data source in Looker Studio.
-- Build a pivot table with country_name as rows, month as columns,
-- avg_carbon_intensity_gco2_kwh as the metric, and heatmap styling applied.
select
    country_name,
    format_date('%Y-%m', date_key) as year_month,
    round(avg(avg_carbon_intensity_gco2_kwh), 1) as avg_carbon_intensity_gco2_kwh,
    round(avg(avg_renewable_pct), 1)              as avg_renewable_pct,
from `YOUR_GCP_PROJECT.european_energy.fct_grid_carbon_intensity`
group by 1, 2
order by 1, 2
