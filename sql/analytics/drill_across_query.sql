USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

-- Daily summary combining weather AND air quality per city
-- This is only possible because DIM_CITY and DIM_DATE are conformed
SELECT
    c.city_name,
    d.full_date,
    d.day_of_week,
    ROUND(AVG(w.temperature_c), 2)  AS avg_temp,
    ROUND(AVG(w.humidity_pct), 2)   AS avg_humidity,
    ROUND(AVG(a.pm2_5), 2)          AS avg_pm25,
    ROUND(AVG(a.uv_index), 2)       AS avg_uv,
    CASE
        WHEN AVG(a.pm2_5) > 75 THEN 'Unhealthy'
        WHEN AVG(a.pm2_5) > 35 THEN 'Moderate'
        ELSE 'Good'
    END AS air_quality_category
FROM FACT_WEATHER_READINGS w
JOIN FACT_AIR_QUALITY_READINGS a
    ON w.city_sk = a.city_sk
    AND w.date_sk = a.date_sk
    AND HOUR(w.recorded_at) = HOUR(a.recorded_at)
JOIN DIM_CITY c ON w.city_sk = c.city_sk AND c.is_current = TRUE
JOIN DIM_DATE d ON w.date_sk = d.date_sk
GROUP BY c.city_name, d.full_date, d.day_of_week
ORDER BY d.full_date, c.city_name;