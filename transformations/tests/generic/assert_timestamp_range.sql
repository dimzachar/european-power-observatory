/*
  Generic test: verify that timestamps fall within an expected range.
  This prevents stale data from being accidentally loaded.
*/
with validation as (
    select
        ts_hour,
    from {{ ref('stg_entsoe__generation') }}
),

validation_errors as (
    select *
    from validation
    where
        ts_hour < '2024-01-01'
        or ts_hour > '2026-12-31'
)

select *
from validation_errors
