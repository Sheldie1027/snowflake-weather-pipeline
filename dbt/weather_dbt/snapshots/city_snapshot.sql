{% snapshot city_snapshot %}

{{
    config(
        target_schema='DBT_DEV',
        unique_key='city_name',
        strategy='check',
        check_cols=['country', 'latitude', 'longitude']
    )
}}

select
    city_name,
    country,
    latitude,
    longitude
from {{ ref('stg_weather') }}
group by city_name, country, latitude, longitude

{% endsnapshot %}