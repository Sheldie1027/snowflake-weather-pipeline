with weather as (

    select * from {{ ref('stg_weather') }}

),

daily as (

    select
        city_name,
        date(recorded_at) as reading_date,
        round(avg(temperature_c), 2) as avg_temp,
        max(temperature_c) as max_temp,
        min(temperature_c) as min_temp,
        round(avg(humidity_pct), 2) as avg_humidity,
        round(avg(windspeed_kmh), 2) as avg_windspeed,
        count(*) as reading_cnt
    from weather
    group by city_name, date(recorded_at)

)

select * from daily
