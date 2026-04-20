-- Overview KPIs: today's summary metrics
with latest_date as (
    select max(date_key) as today from {{ ref('fct_renewable_kpi') }}
),
kpis as (
    select
        round(avg(renewable_pct), 1) as avg_renewable_pct_all_countries,
        round(sum(renewable_mwh) / 1000, 1) as total_renewable_gwh,
        round(sum(total_mwh) / 1000, 1) as total_gwh,
        count(*) as countries_reporting
    from {{ ref('fct_renewable_kpi') }}
    where date_key = (select today from latest_date)
),
top_country as (
    select
        country_name,
        round(renewable_pct, 1) as renewable_pct
    from {{ ref('fct_renewable_kpi') }}
    where date_key = (select today from latest_date)
    order by renewable_pct desc
    limit 1
)

select
    k.avg_renewable_pct_all_countries,
    k.total_renewable_gwh,
    k.total_gwh,
    k.countries_reporting,
    t.country_name as top_country,
    t.renewable_pct as top_country_pct
from kpis k, top_country t