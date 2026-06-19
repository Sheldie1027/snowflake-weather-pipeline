-- ============================================================
-- Week 1 Project: Analytics Queries
-- Run these in Snowflake after the pipeline has loaded data
-- ============================================================

USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

-- Query 1: Daily average temperature per city
SELECT
    d.full_date,
    c.city_name,
    ROUND(AVG(f.temperature_c), 2)  AS avg_temp,
    MAX(f.temperature_c)            AS max_temp,
    MIN(f.temperature_c)            AS min_temp
FROM FACT_WEATHER_READINGS f
JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
JOIN DIM_DATE d ON f.date_sk = d.date_sk
GROUP BY d.full_date, c.city_name
ORDER BY d.full_date, avg_temp DESC;

-- Query 2: Hottest hour of each day per city using ROW_NUMBER
WITH hourly_ranked AS (
    SELECT
        c.city_name,
        d.full_date,
        HOUR(f.recorded_at)                     AS hour_of_day,
        f.temperature_c,
        ROW_NUMBER() OVER (
            PARTITION BY f.city_sk, d.full_date
            ORDER BY f.temperature_c DESC
        ) AS temp_rank
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
    JOIN DIM_DATE d ON f.date_sk = d.date_sk
)
SELECT city_name, full_date, hour_of_day, temperature_c AS peak_temp
FROM hourly_ranked
WHERE temp_rank = 1
ORDER BY full_date, city_name;

-- Query 3: 7-day rolling average temperature per city
SELECT
    c.city_name,
    DATE(f.recorded_at)                                 AS reading_date,
    ROUND(AVG(f.temperature_c), 2)                      AS daily_avg,
    ROUND(AVG(AVG(f.temperature_c)) OVER (
        PARTITION BY f.city_sk
        ORDER BY DATE(f.recorded_at)
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2)                                                AS rolling_7day_avg
FROM FACT_WEATHER_READINGS f
JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
GROUP BY c.city_name, f.city_sk, DATE(f.recorded_at)
ORDER BY c.city_name, reading_date;

-- Query 4: Cities ranked by average temperature overall
SELECT
    c.city_name,
    c.state,
    ROUND(AVG(f.temperature_c), 2)                      AS avg_temp,
    DENSE_RANK() OVER (ORDER BY AVG(f.temperature_c) DESC) AS temp_rank
FROM FACT_WEATHER_READINGS f
JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
GROUP BY c.city_name, c.state
ORDER BY temp_rank;

-- Query 5: Days exceeding 38 degrees using CTE
WITH hot_days AS (
    SELECT
        c.city_name,
        DATE(f.recorded_at)         AS reading_date,
        MAX(f.temperature_c)        AS peak_temp,
        COUNT(*)                    AS hours_above_threshold
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
    WHERE f.temperature_c > 38
    GROUP BY c.city_name, DATE(f.recorded_at)
)
SELECT
    city_name,
    reading_date,
    ROUND(peak_temp, 2)     AS peak_temp,
    hours_above_threshold
FROM hot_days
ORDER BY peak_temp DESC;