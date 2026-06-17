-- Number each reading per city ordered by time
SELECT
    city,
    recorded_at,
    temperature_c,
    ROW_NUMBER() OVER (
        PARTITION BY city 
        ORDER BY recorded_at ASC
    ) AS reading_number
FROM RAW_WEATHER_LOAD
ORDER BY city, recorded_at;


-- Rank cities by temperature for each hour
SELECT
    city,
    recorded_at,
    temperature_c,
    RANK() OVER (
        PARTITION BY DATE_TRUNC('hour', recorded_at)
        ORDER BY temperature_c DESC
    ) AS temp_rank,
    DENSE_RANK() OVER (
        PARTITION BY DATE_TRUNC('hour', recorded_at)
        ORDER BY temperature_c DESC
    ) AS temp_dense_rank
FROM RAW_WEATHER_LOAD
ORDER BY recorded_at, temp_rank;


-- For each city, show current temp, previous hour temp, and the difference
SELECT
    city,
    recorded_at,
    temperature_c,
    LAG(temperature_c, 1) OVER (
        PARTITION BY city 
        ORDER BY recorded_at
    ) AS prev_hour_temp,
    temperature_c - LAG(temperature_c, 1) OVER (
        PARTITION BY city 
        ORDER BY recorded_at
    ) AS temp_change
FROM RAW_WEATHER_LOAD
ORDER BY city, recorded_at;


-- Running average temperature per city over time
SELECT
    city,
    recorded_at,
    temperature_c,
    ROUND(AVG(temperature_c) OVER (
        PARTITION BY city
        ORDER BY recorded_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2) AS running_avg_temp,
    ROUND(AVG(temperature_c) OVER (
        PARTITION BY city
        ORDER BY recorded_at
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_3hr
FROM RAW_WEATHER_LOAD
ORDER BY city, recorded_at;


-- For each reading, show the day's first and highest temperature for that city
SELECT
    city,
    recorded_at,
    temperature_c,
    FIRST_VALUE(temperature_c) OVER (
        PARTITION BY city, DATE(recorded_at)
        ORDER BY recorded_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_reading_of_day,
    MAX(temperature_c) OVER (
        PARTITION BY city, DATE(recorded_at)
    ) AS daily_max_temp
FROM RAW_WEATHER_LOAD
ORDER BY city, recorded_at;