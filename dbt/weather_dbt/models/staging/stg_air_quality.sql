with source as (

    select * from {{ source('raw', 'raw_air_quality') }}

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by city, recorded_at
            order by loaded_at desc
        ) as rn
    from source
    where pm2_5 is not null

),

cleaned as (

    select
        city as city_name,
        country,
        latitude,
        longitude,
        recorded_at,
        pm2_5,
        uv_index,
        carbon_monoxide,
        pipeline_run_id,
        loaded_at
    from deduplicated
    where rn = 1

)

select * from cleaned