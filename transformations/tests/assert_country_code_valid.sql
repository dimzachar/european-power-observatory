/*
  Singular test: verify country_code exists in dim_country seed.
  Ensures no invalid country codes slip into the warehouse.
*/
with source_countries as (
    select distinct country_code
    from {{ ref('fct_renewable_kpi') }}
),
valid_countries as (
    select country_code
    from {{ ref('dim_country') }}
),
invalid_countries as (
    select s.country_code
    from source_countries s
    left join valid_countries v
        on s.country_code = v.country_code
    where v.country_code is null
)

select *
from invalid_countries
