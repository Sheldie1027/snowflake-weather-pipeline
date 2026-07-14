-- NOTE: These queries target the original hand-built star schema in
-- WEATHER_DB.MARTS (Weeks 1-2), which has been superseded by the dbt models
-- in WEATHER_DB.DBT_PROD. Kept as a record of the SQL techniques used.

USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

--ROLLUP — hierarchical subtotals
-- Daily average temperature with subtotals by city and grand total

WITH base AS (
    SELECT
        c.country,
        c.city_name,
        DATE(f.recorded_at) AS reading_date,
        f.temperature_c
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
)
SELECT
    country,
    city_name,
    reading_date,
    ROUND(AVG(temperature_c), 2) AS avg_temp,
    COUNT(*)                     AS readings
FROM base
GROUP BY ROLLUP(country, city_name, reading_date);


--GROUPING() function — identify subtotal rows

WITH base AS (
    SELECT
        c.country,
        c.city_name,
        DATE(f.recorded_at) AS reading_date,
        f.temperature_c
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
)
SELECT
    country,
    CASE WHEN GROUPING(city_name) = 1 THEN 'ALL CITIES' ELSE city_name END AS city,
    CASE WHEN GROUPING(reading_date) = 1 THEN 'ALL DATES' ELSE reading_date::VARCHAR END AS reading_date,
    ROUND(AVG(temperature_c), 2) AS avg_temp,
    COUNT(*)                     AS readings,
FROM base
GROUP BY ROLLUP(country, city_name, reading_date);


--CUBE — all possible combinations
-- All combinations: by city only, by date only, by city+date, and grand total

WITH base AS (
    SELECT
        c.country,
        c.city_name,
        DATE(f.recorded_at) AS reading_date,
        f.temperature_c
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
)
SELECT
    CASE WHEN GROUPING(city_name) = 1 THEN 'ALL CITIES' ELSE city_name END AS city,
    CASE WHEN GROUPING(reading_date) = 1 THEN 'ALL DATES' ELSE reading_date::VARCHAR END AS reading_date,
    ROUND(AVG(temperature_c), 2)  AS avg_temp,
    COUNT(*)                        AS readings
FROM base
GROUP BY CUBE(city_name, reading_date)
ORDER BY city, reading_date;


--GROUPING SETS — choose exactly what you want
--per city summary AND per date summary AND grand total but NOT the city+date combination

WITH base AS (
    SELECT
        c.country,
        c.city_name,
        DATE(f.recorded_at) AS reading_date,
        f.temperature_c
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
)
SELECT
    CASE WHEN GROUPING(city_name) = 1 THEN 'ALL CITIES' ELSE city_name END AS city,
    CASE WHEN GROUPING(reading_date) = 1 THEN 'ALL DATES' ELSE reading_date::VARCHAR END AS reading_date,
    ROUND(AVG(temperature_c), 2)  AS avg_temp,
    COUNT(*)                        AS readings
FROM base
GROUP BY GROUPING SETS (
    (city_name),          -- subtotal per city
    (reading_date),  -- subtotal per date
    ()                      -- grand total
)
ORDER BY city, reading_date;
