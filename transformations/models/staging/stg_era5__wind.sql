{{ config(
    materialized='view',
    tags=['staging', 'era5']
) }}

with source as (
    select
        timestamp_micros(div(cast(timestamp as int64), 1000)) as source_ts,
        lat,
        lon,
        country,
        variable,
        value
    from {{ source('raw', 'era5_weather') }}
),

wind_data as (
    select
        source_ts as ts_hour,
        lat,
        lon,
        country,
        variable,
        value,
        date(source_ts) as date_key,
        extract(hour from source_ts) as hour_of_day
    from source
    where
        variable in ('u100', 'v100')
        and source_ts is not null
),

pivoted as (
    select
        ts_hour,
        date_key,
        hour_of_day,
        lat,
        lon,
        country,
        max(case when variable = 'u100' then value end) as wind_100m_u,
        max(case when variable = 'v100' then value end) as wind_100m_v
    from wind_data
    group by 1, 2, 3, 4, 5, 6
),

with_derived as (
    select
        ts_hour,
        date_key,
        hour_of_day,
        lat,
        lon,
        country as country_code,
        {{ country_name_from_code('country') }} as country_name,
        wind_100m_u,
        wind_100m_v,
        sqrt(wind_100m_u * wind_100m_u + wind_100m_v * wind_100m_v) as wind_speed_100m,
        atan2(wind_100m_v, wind_100m_u) * 180 / 3.14159265 as wind_direction_degrees
    from pivoted
)

select * from with_derived
