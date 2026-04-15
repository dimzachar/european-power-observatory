{{ config(
    materialized='view',
    tags=['staging', 'era5']
) }}

with source as (
    select
        timestamp_micros(div(cast(timestamp as int64), 1000)) as source_ts,
        lat,
        lon,
        variable,
        value,
        country
    from {{ source('raw', 'era5_weather') }}
),

solar_data as (
    select
        source_ts as ts_hour,
        lat,
        lon,
        variable,
        value,
        date(source_ts) as date_key,
        extract(hour from source_ts) as hour_of_day,
    from source
    where
        variable in ('ssrd', 'tcc', 't2m')
        and source_ts is not null
),

pivoted as (
    select
        ts_hour,
        date_key,
        hour_of_day,
        lat,
        lon,
        max(case when variable = 'ssrd' then value end) as solar_radiation_jm2,
        max(case when variable = 'tcc' then value end) as cloud_cover_fraction,
        max(case when variable = 't2m' then value end) as temp_2m_kelvin,
    from solar_data
    group by 1, 2, 3, 4, 5
),

with_derived as (
    select
        ts_hour,
        date_key,
        hour_of_day,
        lat,
        lon,
        'GR' as country_code,
        'Greece' as country_name,
        solar_radiation_jm2,
        cloud_cover_fraction,
        temp_2m_kelvin,
        round(temp_2m_kelvin - 273.15, 2) as temp_2m_celsius,
        round(coalesce(solar_radiation_jm2 / 3600.0, 0), 2) as solar_radiation_wm2,
    from pivoted
)

select * from with_derived
