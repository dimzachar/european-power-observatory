{{ config(
    materialized='table',
    tags=['intermediate', 'weather', 'generation']
) }}

with hourly_gen as (
    select
        ts_hour,
        country_code,
        country_name,
        date_key,
        hour_of_day,
        energy_source,
        actual_mw
    from {{ ref('stg_entsoe__generation') }}
),

hourly_wind as (
    select
        ts_hour,
        country_code,
        country_name,
        avg(wind_speed_100m) as avg_wind_speed
    from {{ ref('stg_era5__wind') }}
    group by 1, 2, 3
),

hourly_solar as (
    select
        ts_hour,
        country_code,
        country_name,
        avg(solar_radiation_wm2) as avg_solar_radiation,
        avg(temp_2m_celsius) as avg_temp
    from {{ ref('stg_era5__solar') }}
    group by 1, 2, 3
),

joined as (
    select
        g.ts_hour,
        g.date_key,
        g.hour_of_day,
        g.country_code,
        g.country_name,
        g.energy_source,
        g.actual_mw,
        w.avg_wind_speed,
        s.avg_solar_radiation,
        s.avg_temp
    from hourly_gen g
    left join hourly_wind w on g.ts_hour = w.ts_hour and g.country_code = w.country_code
    left join hourly_solar s on g.ts_hour = s.ts_hour and g.country_code = s.country_code
)

select * from joined
order by ts_hour desc, country_code, energy_source
