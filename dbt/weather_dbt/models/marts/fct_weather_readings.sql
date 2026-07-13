{{
    config(
        materialized='incremental',
        unique_key='reading_sk',
        incremental_strategy='merge'
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
        {{ dbt_utils.generate_surrogate_key(['w.city_name', 'w.recorded_at']) }} as reading_sk,
        c.city_sk,
        w.recorded_at,
        date(w.recorded_at) as reading_date,
        w.temperature_c,
        {{ celsius_to_fahrenheit('w.temperature_c') }} as temperature_f,
        w.humidity_pct,
        w.windspeed_kmh,
        w.weather_code,
        w.pipeline_run_id
    from weather as w
    inner join city as c on w.city_name = c.city_name

    {% if is_incremental() %}
        where w.recorded_at > (select max(recorded_at) from {{ this }})  -- noqa: RF02
    {% endif %}

)

select * from final
