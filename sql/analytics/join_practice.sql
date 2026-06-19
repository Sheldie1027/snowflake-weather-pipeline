USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

-- Create and populate DIM_DATE for the days in your dataset
CREATE TABLE DIM_DATE (
    date_sk        INTEGER PRIMARY KEY,
    full_date      DATE    NOT NULL,
    day_of_week    VARCHAR(10),
    day_num        INTEGER,
    week_of_year   INTEGER,
    month_num      INTEGER,
    month_name     VARCHAR(10),
    quarter        INTEGER,
    year           INTEGER,
    is_weekend     BOOLEAN
);

-- Populate with dates covering your dataset
INSERT INTO DIM_DATE
SELECT
    TO_NUMBER(TO_VARCHAR(d.date_val, 'YYYYMMDD'))   AS date_sk,
    d.date_val                                       AS full_date,
    DAYNAME(d.date_val)                              AS day_of_week,
    DAYOFWEEK(d.date_val)                            AS day_num,
    WEEKOFYEAR(d.date_val)                           AS week_of_year,
    MONTH(d.date_val)                                AS month_num,
    MONTHNAME(d.date_val)                            AS month_name,
    QUARTER(d.date_val)                              AS quarter,
    YEAR(d.date_val)                                 AS year,
    DAYOFWEEK(d.date_val) IN (1, 7)                 AS is_weekend
FROM (
    SELECT DATEADD(DAY, seq4(), '2026-06-01'::DATE) AS date_val
    FROM TABLE(GENERATOR(ROWCOUNT => 30))
) d;

-- Create a simple weather codes dimension
CREATE TABLE DIM_WEATHER_CODE (
    code_sk     INTEGER PRIMARY KEY AUTOINCREMENT,
    code_value  INTEGER UNIQUE NOT NULL,
    description VARCHAR(200),
    category    VARCHAR(50),
    severity    VARCHAR(20)
);

INSERT INTO DIM_WEATHER_CODE (code_value, description, category, severity) VALUES
    (0,  'Clear sky',                    'Clear',        'Low'),
    (1,  'Mainly clear',                 'Clear',        'Low'),
    (2,  'Partly cloudy',               'Cloudy',       'Low'),
    (3,  'Overcast',                     'Cloudy',       'Low'),
    (45, 'Foggy',                        'Fog',          'Medium'),
    (51, 'Light drizzle',               'Rain',         'Low'),
    (61, 'Slight rain',                  'Rain',         'Medium'),
    (80, 'Slight rain showers',          'Rain',         'Medium'),
    (95, 'Thunderstorm',                 'Thunderstorm', 'High');


CREATE TABLE FACT_WEATHER_READINGS (
    reading_sk      INTEGER AUTOINCREMENT PRIMARY KEY,
    city_sk         INTEGER REFERENCES DIM_CITY(city_sk),
    date_sk         INTEGER REFERENCES DIM_DATE(date_sk),
    weather_code_sk INTEGER REFERENCES DIM_WEATHER_CODE(code_sk),
    recorded_at     TIMESTAMP_NTZ NOT NULL,
    temperature_c   FLOAT,
    humidity_pct    FLOAT,
    windspeed_kmh   FLOAT,
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Load from RAW into FACT by looking up surrogate keys
INSERT INTO FACT_WEATHER_READINGS
    (city_sk, date_sk, weather_code_sk, recorded_at, temperature_c, humidity_pct, windspeed_kmh)
SELECT
    c.city_sk,
    TO_NUMBER(TO_VARCHAR(DATE(r.recorded_at), 'YYYYMMDD'))  AS date_sk,
    COALESCE(w.code_sk, 1)                                   AS weather_code_sk,
    r.recorded_at,
    r.temperature_c,
    r.humidity_pct,
    r.windspeed_kmh
FROM WEATHER_DB.RAW.RAW_WEATHER_API r
JOIN DIM_CITY c
    ON r.city = c.city_nk
    AND c.is_current = TRUE
LEFT JOIN DIM_WEATHER_CODE w
    ON r.weather_code = w.code_value
WHERE r.temperature_c IS NOT NULL;

-- Verify
SELECT COUNT(*) FROM FACT_WEATHER_READINGS;


-- Get weather readings with full city and date context
SELECT
    f.recorded_at,
    c.city_name,
    c.state,
    d.day_of_week,
    f.temperature_c,
    f.humidity_pct
FROM FACT_WEATHER_READINGS f
INNER JOIN DIM_CITY c ON f.city_sk = c.city_sk
INNER JOIN DIM_DATE d ON f.date_sk = d.date_sk
ORDER BY f.recorded_at
LIMIT 20;


-- All weather codes, even ones not present in our data
-- Shows which weather conditions we haven't seen yet
SELECT
    w.code_value,
    w.description,
    w.category,
    COUNT(f.reading_sk) AS times_observed
FROM DIM_WEATHER_CODE w
LEFT JOIN FACT_WEATHER_READINGS f ON w.code_sk = f.weather_code_sk
GROUP BY w.code_value, w.description, w.category
ORDER BY times_observed DESC;


-- Compare each city's temperature to Mumbai's temperature at the same hour
SELECT
    f1.recorded_at,
    c1.city_name                                                AS city,
    f1.temperature_c                                            AS city_temp,
    f2.temperature_c                                            AS mumbai_temp,
    ROUND(f1.temperature_c - f2.temperature_c, 2)              AS diff_from_mumbai
FROM FACT_WEATHER_READINGS f1
JOIN DIM_CITY c1 ON f1.city_sk = c1.city_sk AND c1.is_current = TRUE
JOIN FACT_WEATHER_READINGS f2 ON f1.recorded_at = f2.recorded_at
JOIN DIM_CITY c2 ON f2.city_sk = c2.city_sk AND c2.city_name = 'Mumbai' AND c2.is_current = TRUE
WHERE c1.city_name != 'Mumbai'
ORDER BY f1.recorded_at, c1.city_name
LIMIT 30;


-- Full analytical query: daily summary per city with weather category
WITH daily_stats AS (
    SELECT
        f.city_sk,
        f.date_sk,
        w.category                              AS weather_category,
        ROUND(AVG(f.temperature_c), 2)          AS avg_temp,
        MAX(f.temperature_c)                    AS max_temp,
        ROUND(AVG(f.humidity_pct), 2)           AS avg_humidity,
        COUNT(*)                                AS readings
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_WEATHER_CODE w ON f.weather_code_sk = w.code_sk
    GROUP BY f.city_sk, f.date_sk, w.category
)
SELECT
    d.full_date,
    d.day_of_week,
    c.city_name,
    c.state,
    s.weather_category,
    s.avg_temp,
    s.max_temp,
    s.avg_humidity,
    s.readings,
    RANK() OVER (PARTITION BY d.full_date ORDER BY s.avg_temp DESC) AS daily_temp_rank
FROM daily_stats s
JOIN DIM_CITY c ON s.city_sk = c.city_sk AND c.is_current = TRUE
JOIN DIM_DATE d ON s.date_sk = d.date_sk
ORDER BY d.full_date, daily_temp_rank;