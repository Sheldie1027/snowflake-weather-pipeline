with air_quality as (

    select * from {{ ref('stg_air_quality') }}

),

city as (

    select * from {{ ref('dim_city') }}

),

final as (

    select
        md5(upper(trim(aq.city_name)) || '|' ||
            to_varchar(aq.recorded_at, 'YYYY-MM-DD HH24:MI:SS'))  as reading_sk,
        c.city_sk,
        aq.recorded_at,
        date(aq.recorded_at) as reading_date,
        aq.pm2_5,
        aq.uv_index,
        aq.carbon_monoxide,
        aq.pipeline_run_id
    from air_quality aq
    join city c on aq.city_name = c.city_name

)

select * from final