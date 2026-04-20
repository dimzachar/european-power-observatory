-- Renewable share ranking: which countries had the highest clean energy today?
select
    country_name,
    date_key,
    round(renewable_pct, 1) as renewable_pct,
    round(renewable_mwh, 0) as renewable_mwh,
    round(total_mwh, 0) as total_mwh,
    renewable_sources_active,
    total_sources_active
from `{{ var('project') }}.mart.fct_renewable_kpi`
order by renewable_pct desc
