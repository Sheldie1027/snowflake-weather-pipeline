with source as (

    select * from {{ source('raw', 'raw_air_quality') }}

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
    from source
    where pm2_5 is not null

)

select * from cleaned