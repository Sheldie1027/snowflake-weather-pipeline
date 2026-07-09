with source as (

    select * from {{ source('raw', 'raw_weather_api') }}

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by city, recorded_at
            order by loaded_at desc
        ) as rn
    from source
    where temperature_c is not null

),

cleaned as (

    select
        city as city_name,
        country,
        latitude,
        longitude,
        recorded_at,
        temperature_c,
        humidity_pct,
        windspeed_kmh,
        weather_code,
        pipeline_run_id,
        loaded_at
    from deduplicated
    where rn = 1

)

select * from cleaned