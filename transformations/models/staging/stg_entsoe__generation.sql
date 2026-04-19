{{ config(
    materialized='view',
    tags=['staging', 'entsoe']
) }}

with source as (
    select
        timestamp_micros(div(cast(timestamp as int64), 1000)) as source_ts,
        country,
        energy_source,
        psr_type,
        actual_MW,
        forecast_MW,
        domain
    from {{ source('raw', 'entsoe_generation') }}
),

filtered as (
    select
        timestamp_trunc(source_ts, hour) as ts_hour,
        country as country_code,
        energy_source,
        psr_type as psr_code,
        cast(actual_MW as float64) as actual_mw,
        cast(forecast_MW as float64) as forecast_mw,
        {{ country_name_from_code('country') }} as country_name,
        date(source_ts) as date_key,
        extract(hour from source_ts) as hour_of_day,
        extract(month from source_ts) as month_of_year
    from source
    where
        source_ts is not null
        and (actual_MW >= 0 or forecast_MW >= 0)
),

-- Deduplicate: keep one row per (ts_hour, country_code, energy_source),
-- preferring rows where actual_mw is not null.
deduped as (
    select *
    from filtered
    qualify row_number() over (
        partition by ts_hour, country_code, energy_source
        order by actual_mw desc nulls last
    ) = 1
),

cleaned as (
    select
        ts_hour,
        country_code,
        country_name,
        date_key,
        hour_of_day,
        month_of_year,
        energy_source,
        psr_code,
        actual_mw,
        forecast_mw,
        case
            when actual_mw is null and forecast_mw is not null then forecast_mw
            when actual_mw is not null and forecast_mw is null then actual_mw
            else actual_mw
        end as generation_mw,
        case
            when actual_mw is not null and forecast_mw is not null then
                abs(actual_mw - forecast_mw) / greatest(forecast_mw, 0.01)
            else null
        end as forecast_error_pct
    from deduped
)

select * from cleaned
