{{ config(
    materialized='table',
    tags=['mart', 'carbon']
) }}

/*
  Daily carbon intensity per country — the dashboard-facing mart table.
  Answers: "When is the cleanest time to use electricity in country X?"
  Aggregates int_carbon_intensity from hourly to daily, and adds
  cleanest/dirtiest hour context per country per day.
  typical_cleanest_hour: the hour of day (0-23) that is most frequently
  the cleanest hour across all days for that country. Safe to show in
  a country-level table without averaging decimals.
*/

with daily_agg as (
    select
        date_key,
        country_code,
        country_name,
        round(avg(carbon_intensity_gco2_kwh), 2)  as avg_carbon_intensity_gco2_kwh,
        round(min(carbon_intensity_gco2_kwh), 2)  as min_carbon_intensity_gco2_kwh,
        round(max(carbon_intensity_gco2_kwh), 2)  as max_carbon_intensity_gco2_kwh,
        round(avg(renewable_mw * 100.0 / greatest(total_mw, 0.001)), 2) as avg_renewable_pct,
        count(*) as hours_reported
    from {{ ref('int_carbon_intensity') }}
    group by 1, 2, 3
),

cleanest_hour as (
    select
        date_key,
        country_code,
        hour_of_day as cleanest_hour_of_day,
        carbon_intensity_gco2_kwh as cleanest_hour_intensity
    from {{ ref('int_carbon_intensity') }}
    qualify row_number() over (
        partition by date_key, country_code
        order by carbon_intensity_gco2_kwh asc
    ) = 1
),

dirtiest_hour as (
    select
        date_key,
        country_code,
        hour_of_day as dirtiest_hour_of_day,
        carbon_intensity_gco2_kwh as dirtiest_hour_intensity
    from {{ ref('int_carbon_intensity') }}
    qualify row_number() over (
        partition by date_key, country_code
        order by carbon_intensity_gco2_kwh desc
    ) = 1
),

-- Most frequent cleanest hour per country across all days.
-- Step 1: count how many days each hour was the cleanest for each country.
-- Step 2: pick the hour with the highest count.
typical_cleanest_hour_counts as (
    select
        country_code,
        cleanest_hour_of_day,
        count(*) as day_count
    from cleanest_hour
    group by 1, 2
),

typical_cleanest_hour as (
    select
        country_code,
        cleanest_hour_of_day as typical_cleanest_hour,
    from typical_cleanest_hour_counts
    qualify row_number() over (
        partition by country_code
        order by day_count desc
    ) = 1
)

select
    d.date_key,
    d.country_code,
    d.country_name,
    d.avg_carbon_intensity_gco2_kwh,
    d.min_carbon_intensity_gco2_kwh,
    d.max_carbon_intensity_gco2_kwh,
    d.avg_renewable_pct,
    d.hours_reported,
    c.cleanest_hour_of_day,
    c.cleanest_hour_intensity,
    x.dirtiest_hour_of_day,
    x.dirtiest_hour_intensity,
    round(x.dirtiest_hour_intensity - c.cleanest_hour_intensity, 2) as daily_intensity_range_gco2_kwh,
    t.typical_cleanest_hour
from daily_agg d
left join cleanest_hour c on d.date_key = c.date_key and d.country_code = c.country_code
left join dirtiest_hour x on d.date_key = x.date_key and d.country_code = x.country_code
left join typical_cleanest_hour t on d.country_code = t.country_code
order by date_key desc, avg_carbon_intensity_gco2_kwh asc
