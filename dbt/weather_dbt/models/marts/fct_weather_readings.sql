{{
    config(
        materialized='incremental',
        unique_key='reading_sk'
    )
}}

with weather as (

    select * from {{ ref('stg_weather') }}

),

city as (

    select * from {{ ref('dim_city') }}

),

final as (

    select
        md5(upper(trim(w.city_name)) || '|' ||
            to_varchar(w.recorded_at, 'YYYY-MM-DD HH24:MI:SS'))  as reading_sk,
        c.city_sk,
        w.recorded_at,
        date(w.recorded_at) as reading_date,
        w.temperature_c,
        w.humidity_pct,
        w.windspeed_kmh,
        w.weather_code,
        w.pipeline_run_id
    from weather w
    join city c on w.city_name = c.city_name

    {% if is_incremental() %}
        -- only process rows newer than what's already loaded
        where w.recorded_at > (select max(recorded_at) from {{ this }})
    {% endif %}

)

select * from final 