-- Trends: renewable % over time per country (last 30 days)
with recent as (
    select
        date_key,
        country_code,
        country_name,
        renewable_pct,
        renewable_mwh,
        total_mwh
    from {{ ref('fct_renewable_kpi') }}
    where date_key >= date_sub(current_date(), interval 30 day)
)
select
    country_name,
    date_key,
    round(renewable_pct, 1) as renewable_pct,
    round(renewable_mwh / 1000, 1) as renewable_gwh,
    round(total_mwh / 1000, 1) as total_gwh
from recent
order by country_name, date_key