{{ config(materialized='table') }}

with weather as (

    select * from {{ ref('fct_weather_readings') }}

),

air_quality as (

    select * from {{ ref('fct_air_quality_readings') }}

),

city as (

    select * from {{ ref('dim_city') }}

),

daily as (

    select
        c.city_name,
        w.reading_date,
        round(avg(w.temperature_c), 2) as avg_temp,
        max(w.temperature_c) as max_temp,
        min(w.temperature_c) as min_temp,
        round(avg(w.humidity_pct), 2) as avg_humidity,
        round(avg(w.windspeed_kmh), 2) as avg_windspeed,
        round(avg(aq.pm2_5), 2) as avg_pm25,
        round(avg(aq.uv_index), 2) as avg_uv,
        count(distinct w.reading_sk) as weather_reading_cnt
    from weather as w
    inner join city as c
        on w.city_sk = c.city_sk
    left join air_quality as aq
        on
            w.city_sk = aq.city_sk
            and w.reading_date = aq.reading_date
            and hour(w.recorded_at) = hour(aq.recorded_at)
    group by c.city_name, w.reading_date

),

final as (

    select
        *,
        case
            when avg_pm25 > 75 then 'Unhealthy'
            when avg_pm25 > 35 then 'Moderate'
            else 'Good'
        end as air_quality_category
    from daily

)

select * from final
