-- Fuel breakdown: daily generation by energy source per country
select
    date_key,
    country_name,
    energy_source,
    round(total_mwh / 1000, 1) as total_gwh,
    round(pct_of_total, 1) as pct_of_total
from {{ ref('int_daily_generation') }}
where total_mwh > 0
order by date_key desc, pct_of_total desc