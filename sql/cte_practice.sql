USE DATABASE WEATHER_DB;
USE SCHEMA RAW;

-- Basic CTE: give a subquery a name
WITH city_averages AS (
    SELECT
        city,
        ROUND(AVG(temperature_c), 2) AS avg_temp,
        ROUND(AVG(humidity_pct), 2)  AS avg_humidity,
        COUNT(*)                      AS reading_count
    FROM RAW_WEATHER_API
    GROUP BY city
)
SELECT *
FROM city_averages
ORDER BY avg_temp DESC;


-- Step 1: get hourly data with date parts
-- Step 2: get daily summaries from step 1
-- Step 3: rank days by temperature from step 2
-- All in one readable query

WITH hourly_enriched AS (
    SELECT
        city,
        DATE(recorded_at)   AS reading_date,
        HOUR(recorded_at)   AS reading_hour,
        temperature_c,
        humidity_pct,
        windspeed_kmh
    FROM RAW_WEATHER_API
    WHERE temperature_c IS NOT NULL
),

daily_summary AS (
    SELECT
        city,
        reading_date,
        ROUND(AVG(temperature_c), 2)    AS avg_temp,
        MAX(temperature_c)              AS max_temp,
        MIN(temperature_c)              AS min_temp,
        ROUND(AVG(humidity_pct), 2)     AS avg_humidity
    FROM hourly_enriched
    GROUP BY city, reading_date
),

ranked_days AS (
    SELECT
        city,
        reading_date,
        avg_temp,
        max_temp,
        min_temp,
        avg_humidity,
        RANK() OVER (PARTITION BY city ORDER BY avg_temp DESC) AS hottest_day_rank
    FROM daily_summary
)

SELECT *
FROM ranked_days
WHERE hottest_day_rank <= 3
ORDER BY city, hottest_day_rank;


-- Subquery version (hard to read, especially when nested 3 levels deep)
SELECT city, reading_date, avg_temp
FROM (
    SELECT
        city,
        DATE(recorded_at) AS reading_date,
        ROUND(AVG(temperature_c), 2) AS avg_temp
    FROM RAW_WEATHER_API
    WHERE temperature_c IS NOT NULL
    GROUP BY city, DATE(recorded_at)
) daily
WHERE avg_temp > 30
ORDER BY avg_temp DESC;

-- CTE version (same result, much cleaner)
WITH daily_averages AS (
    SELECT
        city,
        DATE(recorded_at)            AS reading_date,
        ROUND(AVG(temperature_c), 2) AS avg_temp
    FROM RAW_WEATHER_API
    WHERE temperature_c IS NOT NULL
    GROUP BY city, DATE(recorded_at)
)
SELECT city, reading_date, avg_temp
FROM daily_averages
WHERE avg_temp > 30
ORDER BY avg_temp DESC;


-- Find hours where temperature was significantly above that city's daily average
-- This is the kind of analytical query that goes in your project's insights section

WITH daily_city_avg AS (
    SELECT
        city,
        DATE(recorded_at) AS reading_date,
        AVG(temperature_c) AS daily_avg_temp,
        STDDEV(temperature_c) AS daily_stddev_temp
    FROM RAW_WEATHER_API
    WHERE temperature_c IS NOT NULL
    GROUP BY city, DATE(recorded_at)
),

readings_with_context AS (
    SELECT
        r.city,
        r.recorded_at,
        r.temperature_c,
        d.daily_avg_temp,
        d.daily_stddev_temp,
        r.temperature_c - d.daily_avg_temp AS deviation_from_avg
    FROM RAW_WEATHER_API r
    JOIN daily_city_avg d
        ON r.city = d.city
        AND DATE(r.recorded_at) = d.reading_date
    WHERE r.temperature_c IS NOT NULL
)

SELECT
    city,
    recorded_at,
    temperature_c,
    ROUND(daily_avg_temp, 2)       AS daily_avg,
    ROUND(deviation_from_avg, 2)   AS deviation
FROM readings_with_context
WHERE ABS(deviation_from_avg) > 2  -- more than 2 degrees from daily average
ORDER BY ABS(deviation_from_avg) DESC
LIMIT 20;