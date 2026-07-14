-- NOTE: These queries target the original hand-built star schema in
-- WEATHER_DB.MARTS (Weeks 1-2), which has been superseded by the dbt models
-- in WEATHER_DB.DBT_PROD. Kept as a record of the SQL techniques used.

--- Query 1: Weather + Air Quality correlation per city

USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

-- Do hotter days have worse air quality? Correlation per city.
WITH daily_metrics AS (
    SELECT
        c.city_name,
        DATE(w.recorded_at)            AS reading_date,
        ROUND(AVG(w.temperature_c), 2) AS avg_temp,
        ROUND(AVG(a.pm2_5), 2)         AS avg_pm25
    FROM FACT_WEATHER_READINGS w
    JOIN FACT_AIR_QUALITY_READINGS a
        ON w.city_sk = a.city_sk
        AND w.date_sk = a.date_sk
        AND HOUR(w.recorded_at) = HOUR(a.recorded_at)
    JOIN DIM_CITY c ON w.city_sk = c.city_sk AND c.is_current = TRUE
    GROUP BY c.city_name, DATE(w.recorded_at)
)
SELECT
    city_name,
    COUNT(*)                                  AS days,
    ROUND(CORR(avg_temp, avg_pm25), 3)        AS temp_pm25_correlation
FROM daily_metrics
GROUP BY city_name
ORDER BY temp_pm25_correlation DESC;


---Query 2: Date spine to find data gaps

-- Generate every date in your range and find which cities are missing data
WITH date_spine AS (
    SELECT DATEADD(DAY, seq4(), '2026-06-01'::DATE) AS expected_date
    FROM TABLE(GENERATOR(ROWCOUNT => 30))
    WHERE expected_date <= CURRENT_DATE()
),
city_dates AS (
    SELECT DISTINCT c.city_name, DATE(f.recorded_at) AS actual_date
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
)
SELECT
    ds.expected_date,
    c.city_name,
    CASE WHEN cd.actual_date IS NULL THEN 'MISSING' ELSE 'OK' END AS data_status
FROM date_spine ds
CROSS JOIN (SELECT DISTINCT city_name FROM city_dates) c
LEFT JOIN city_dates cd
    ON ds.expected_date = cd.actual_date AND c.city_name = cd.city_name
WHERE ds.expected_date >= '2026-06-09'  -- your pipeline start
ORDER BY ds.expected_date, c.city_name;


---Query 3: Ranking with multiple window functions

-- For each city: rank days by temperature, show the running max, and day-over-day change
SELECT
    c.city_name,
    DATE(f.recorded_at)                          AS reading_date,
    ROUND(AVG(f.temperature_c), 2)               AS avg_temp,
    RANK() OVER (
        PARTITION BY c.city_name
        ORDER BY AVG(f.temperature_c) DESC
    )                                            AS hottest_day_rank,
    ROUND(MAX(AVG(f.temperature_c)) OVER (
        PARTITION BY c.city_name
        ORDER BY DATE(f.recorded_at)
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2)                                        AS running_max_temp,
    ROUND(AVG(f.temperature_c) - LAG(AVG(f.temperature_c)) OVER (
        PARTITION BY c.city_name
        ORDER BY DATE(f.recorded_at)
    ), 2)                                        AS day_over_day_change
FROM FACT_WEATHER_READINGS f
JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
GROUP BY c.city_name, DATE(f.recorded_at)
ORDER BY c.city_name, reading_date;