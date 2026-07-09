{{ config(severity='warn') }}

-- Weather temperatures should be physically sensible.
-- This test fails if any reading is above 60C or below -50C.

select
    city_name,
    recorded_at,
    temperature_c
from {{ ref('stg_weather') }}
where temperature_c > 60
   or temperature_c < -50