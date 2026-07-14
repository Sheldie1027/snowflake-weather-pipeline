-- COMPLETENESS TEST
-- Every configured city must appear in the daily summary mart.
--
-- Chennai was silently absent from this mart for weeks while every validity
-- test passed, because the mart joins from weather and Chennai had air quality
-- data but no weather data. Nothing errored; the join simply produced nothing.
--
-- Singular tests fail if they return rows. This returns any expected city that
-- is MISSING, so an empty result means all cities are present.

with expected as (

    select column1 as city_name
    from values
        ('Mumbai'),
        ('Bangalore'),
        ('Delhi'),
        ('Chennai')

),

actual as (

    select distinct city_name
    from {{ ref('mart_city_daily_summary') }}

)

select e.city_name
from expected e
left join actual a
    on e.city_name = a.city_name
where a.city_name is null