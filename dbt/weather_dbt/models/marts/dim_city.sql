with weather as (

    select distinct
        city_name,
        country,
        latitude,
        longitude
    from {{ ref('stg_weather') }}

),

final as (

    select
        md5(upper(trim(city_name)))  as city_sk,
        city_name,
        country,
        latitude,
        longitude
    from weather

)

select * from final