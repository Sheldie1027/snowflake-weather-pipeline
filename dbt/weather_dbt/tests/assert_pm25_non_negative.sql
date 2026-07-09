-- PM2.5 cannot be negative. Flag any negative readings.

select
    city_name,
    recorded_at,
    pm2_5
from {{ ref('stg_air_quality') }}
where pm2_5 < 0