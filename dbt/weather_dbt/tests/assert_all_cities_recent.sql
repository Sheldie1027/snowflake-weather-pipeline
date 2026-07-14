-- COMPLETENESS TEST
-- Every city must have data from within the last 3 days.
--
-- Catches the partial silent failure: three cities updating normally while a
-- fourth quietly stopped. Row counts and validity tests would all still pass.

select
    city_name,
    max(reading_date) as latest_reading
from {{ ref('mart_city_daily_summary') }}
group by city_name
having max(reading_date) < dateadd('day', -3, current_date())