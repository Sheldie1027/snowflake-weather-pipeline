with cities as (

    select
        city_name,
        country,
        latitude,
        longitude
    from {{ ref('cities') }}

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['city_name']) }} as city_sk,
        city_name,
        country,
        latitude,
        longitude
    from cities

)

select * from final