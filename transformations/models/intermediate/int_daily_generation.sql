{{ config(
    materialized='table',
    tags=['intermediate', 'generation']
) }}

with daily as (
    select
        date_key,
        energy_source,
        country_code,
        country_name,
        round(avg(actual_mw), 2) as avg_hourly_mw,
        round(max(actual_mw), 2) as max_hourly_mw,
        round(min(actual_mw), 2) as min_hourly_mw,
        round(sum(actual_mw), 2) as total_mwh,  -- hourly MW sums to MWh
        count(*) as hours_reported,
    from {{ ref('stg_entsoe__generation') }}
    group by 1, 2, 3, 4
),

daily_totals as (
    select
        date_key,
        country_code,
        country_name,
        sum(total_mwh) as total_mwh_all_sources,
    from daily
    group by 1, 2, 3
),

joined as (
    select
        d.date_key,
        d.country_code,
        d.country_name,
        d.energy_source,
        d.avg_hourly_mw,
        d.max_hourly_mw,
        d.min_hourly_mw,
        d.total_mwh,
        d.hours_reported,
        dt.total_mwh_all_sources,
        round(
            d.total_mwh * 100.0 / greatest(dt.total_mwh_all_sources, 0.001), 2
        ) as pct_of_total,
    from daily d
    join daily_totals dt
        on d.date_key = dt.date_key and d.country_code = dt.country_code
)

select * from joined
order by date_key desc, pct_of_total desc
