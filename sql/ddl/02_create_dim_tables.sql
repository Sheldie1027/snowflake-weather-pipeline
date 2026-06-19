-- ============================================================
-- Script 02: Dimension Tables (MARTS schema)
-- ============================================================

USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

CREATE TABLE IF NOT EXISTS DIM_CITY (
    city_sk    INTEGER       AUTOINCREMENT PRIMARY KEY,
    city_nk    VARCHAR(100)  NOT NULL,
    city_name  VARCHAR(100)  NOT NULL,
    state      VARCHAR(100),
    country    VARCHAR(100)  NOT NULL,
    latitude   FLOAT,
    longitude  FLOAT,
    valid_from TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    valid_to   TIMESTAMP_NTZ,
    is_current BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS DIM_DATE (
    date_sk      INTEGER PRIMARY KEY,
    full_date    DATE        NOT NULL,
    day_of_week  VARCHAR(10),
    day_num      INTEGER,
    week_of_year INTEGER,
    month_num    INTEGER,
    month_name   VARCHAR(10),
    quarter      INTEGER,
    year         INTEGER,
    is_weekend   BOOLEAN
);

CREATE TABLE IF NOT EXISTS DIM_WEATHER_CODE (
    code_sk     INTEGER AUTOINCREMENT PRIMARY KEY,
    code_value  INTEGER      UNIQUE NOT NULL,
    description VARCHAR(200),
    category    VARCHAR(50),
    severity    VARCHAR(20)
);

-- Seed data for DIM_CITY
INSERT INTO DIM_CITY (city_nk, city_name, state, country, latitude, longitude)
SELECT * FROM (VALUES
    ('Mumbai',    'Mumbai',    'Maharashtra', 'India', 19.07, 72.88),
    ('Bangalore', 'Bangalore', 'Karnataka',   'India', 12.97, 77.59),
    ('Delhi',     'Delhi',     'Delhi NCR',   'India', 28.70, 77.10),
    ('Chennai',   'Chennai',   'Tamil Nadu',  'India', 13.08, 80.27)
) AS v(city_nk, city_name, state, country, latitude, longitude)
WHERE NOT EXISTS (SELECT 1 FROM DIM_CITY WHERE city_nk = v.city_nk);

-- Seed data for DIM_WEATHER_CODE
INSERT INTO DIM_WEATHER_CODE (code_value, description, category, severity)
SELECT * FROM (VALUES
    (0,  'Clear sky',             'Clear',        'Low'),
    (1,  'Mainly clear',          'Clear',        'Low'),
    (2,  'Partly cloudy',        'Cloudy',       'Low'),
    (3,  'Overcast',              'Cloudy',       'Low'),
    (45, 'Foggy',                 'Fog',          'Medium'),
    (51, 'Light drizzle',        'Rain',         'Low'),
    (61, 'Slight rain',           'Rain',         'Medium'),
    (80, 'Slight rain showers',   'Rain',         'Medium'),
    (95, 'Thunderstorm',          'Thunderstorm', 'High')
) AS v(code_value, description, category, severity)
WHERE NOT EXISTS (SELECT 1 FROM DIM_WEATHER_CODE WHERE code_value = v.code_value);

-- Populate DIM_DATE for 90 days
INSERT INTO DIM_DATE
SELECT
    TO_NUMBER(TO_VARCHAR(d.date_val, 'YYYYMMDD')),
    d.date_val,
    DAYNAME(d.date_val),
    DAYOFWEEK(d.date_val),
    WEEKOFYEAR(d.date_val),
    MONTH(d.date_val),
    MONTHNAME(d.date_val),
    QUARTER(d.date_val),
    YEAR(d.date_val),
    DAYOFWEEK(d.date_val) IN (1, 7)
FROM (
    SELECT DATEADD(DAY, seq4(), '2026-05-01'::DATE) AS date_val
    FROM TABLE(GENERATOR(ROWCOUNT => 90))
) d
WHERE NOT EXISTS (
    SELECT 1 FROM DIM_DATE
    WHERE date_sk = TO_NUMBER(TO_VARCHAR(d.date_val, 'YYYYMMDD'))
);