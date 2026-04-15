/*
  Generic test: verify that generation values are non-negative.
  Negative MW values would indicate corrupt data or parsing errors.
*/
with validation as (
    select
        ts_hour,
        country_code,
        energy_source,
        actual_mw,
    from {{ ref('stg_entsoe__generation') }}
    where actual_mw is not null
),

validation_errors as (
    select *
    from validation
    where actual_mw < 0
)

select *
from validation_errors
