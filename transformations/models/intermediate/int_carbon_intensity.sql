{{ config(
    materialized='table',
    tags=['intermediate', 'carbon']
) }}

/*
  Hourly carbon intensity per country in gCO2/kWh.
  Logic: weighted average of emission factors across the generation mix.
  emission_factor_gco2_kwh comes from the dim_energy_source seed (EEA/IPCC values).
  Sources with no emission factor (null or 0 for renewables/nuclear) are included
  in the denominator so the intensity reflects the full grid mix.
*/

with hourly_gen as (
    select
        ts_hour,
        date_key,
        hour_of_day,
        country_code,
        country_name,
        energy_source,
        actual_mw
    from {{ ref('stg_entsoe__generation') }}
    where actual_mw > 0
),

with_emission_factors as (
    select
        g.ts_hour,
        g.date_key,
        g.hour_of_day,
        g.country_code,
        g.country_name,
        g.energy_source,
        g.actual_mw,
        coalesce(d.emission_factor_gco2_kwh, 0) as emission_factor_gco2_kwh,
        d.fuel_category,
        d.is_renewable,
    from hourly_gen g
    left join {{ ref('dim_energy_source') }} d
        on g.energy_source = d.energy_source
),

hourly_intensity as (
    select
        ts_hour,
        date_key,
        hour_of_day,
        country_code,
        country_name,
        -- weighted average: sum(MW * gCO2/kWh) / sum(MW)
        round(
            sum(actual_mw * emission_factor_gco2_kwh) / greatest(sum(actual_mw), 0.001),
            2
        ) as carbon_intensity_gco2_kwh,
        round(sum(actual_mw), 2)                                          as total_mw,
        round(sum(case when is_renewable then actual_mw else 0 end), 2)   as renewable_mw,
        round(sum(case when not coalesce(is_renewable, false) then actual_mw * emission_factor_gco2_kwh else 0 end), 2) as total_co2_grams_per_hour
    from with_emission_factors
    group by 1, 2, 3, 4, 5
)

select * from hourly_intensity
order by ts_hour desc, country_code
