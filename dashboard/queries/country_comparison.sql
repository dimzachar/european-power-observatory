-- Country comparison: renewable % by country over time
select
    country_name,
    date_key,
    round(renewable_pct, 1) as renewable_pct,
    round(renewable_mwh / 1000, 1) as renewable_gwh,
    round(total_mwh / 1000, 1) as total_gwh
from {{ ref('fct_renewable_kpi') }}
order by date_key desc, renewable_pct desc