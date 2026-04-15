{{ config(
    materialized='table',
    tags=['mart', 'kpi']
) }}

with daily_gen as (
    select
        date_key,
        country_code,
        country_name,
        energy_source,
        total_mwh,
        sum(total_mwh) over (partition by date_key, country_code) as total_mwh_all,
    from {{ ref('int_daily_generation') }}
),

daily_with_share as (
    select
        date_key,
        country_code,
        country_name,
        energy_source,
        total_mwh,
        total_mwh_all,
        round(total_mwh * 100.0 / greatest(total_mwh_all, 0.001), 2) as pct_of_total,
        case
            when energy_source in (
                'Biomass',
                'Geothermal',
                'Hydro Pumped Storage',
                'Hydro Run-of-river and poundage',
                'Hydro Water Reservoir',
                'Marine',
                'Other renewable',
                'Solar',
                'Wind Offshore',
                'Wind Onshore'
            ) then 1
            else 0
        end as is_renewable,
    from daily_gen
),

daily_agg as (
    select
        date_key,
        country_code,
        country_name,
        round(sum(case when is_renewable = 1 then total_mwh else 0 end) * 100.0 / greatest(sum(total_mwh), 0.001), 2) as renewable_pct,
        round(sum(case when is_renewable = 1 then total_mwh else 0 end), 2) as renewable_mwh,
        round(sum(total_mwh), 2) as total_mwh,
        count(distinct case when is_renewable = 1 then energy_source end) as renewable_sources_active,
        count(distinct energy_source) as total_sources_active,
    from daily_with_share
    group by 1, 2, 3
)

select * from daily_agg
order by date_key desc
