-- Weather correlation: generation vs weather conditions
select
    date_key,
    country_name,
    round(total_mwh / 1000, 1) as total_gwh,
    round(renewable_mwh / 1000, 1) as renewable_gwh,
    round(avg_wind_speed, 1) as avg_wind_speed_ms,
    round(avg_solar_radiation, 0) as avg_solar_radiation_wm2,
    round(avg_temperature, 1) as avg_temp_celsius
from {{ ref('int_generation_weather_join') }}
where total_mwh > 0
order by date_key desc