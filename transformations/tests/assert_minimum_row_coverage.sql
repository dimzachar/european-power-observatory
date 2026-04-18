/*
  Singular test: verify minimum row coverage per country per day.
  Each country should have at least 18 hours (75% of 24) of generation data.
*/
with daily_counts as (
    select
        date_key,
        country_code,
        count(*) as hour_count
    from {{ ref('stg_entsoe__generation') }}
    where actual_mw is not null or forecast_mw is not null
    group by date_key, country_code
),
coverage_issues as (
    select
        date_key,
        country_code,
        hour_count
    from daily_counts
    where hour_count < 18
)

select *
from coverage_issues
order by date_key desc, country_code
