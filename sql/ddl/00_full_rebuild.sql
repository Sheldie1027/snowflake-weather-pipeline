-- ============================================================
-- WEATHER INTELLIGENCE PIPELINE — FULL REBUILD SCRIPT
-- Run as ACCOUNTADMIN in a fresh Snowflake account.
-- Recreates: database, schemas, role + grants, all tables
-- (RAW, MARTS star schema, Data Vault), and seed data.
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- ── 1. DATABASE & SCHEMAS ─────────────────────────────────────────────────────
CREATE DATABASE IF NOT EXISTS WEATHER_DB;
USE DATABASE WEATHER_DB;

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS MARTS;
CREATE SCHEMA IF NOT EXISTS DBT_DEV;

-- ── 2. PIPELINE ROLE & GRANTS ─────────────────────────────────────────────────
CREATE ROLE IF NOT EXISTS PIPELINE_ROLE
    COMMENT = 'Least-privilege role for the weather pipeline';

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE PIPELINE_ROLE;
GRANT USAGE ON DATABASE WEATHER_DB  TO ROLE PIPELINE_ROLE;

GRANT USAGE ON SCHEMA WEATHER_DB.RAW     TO ROLE PIPELINE_ROLE;
GRANT USAGE ON SCHEMA WEATHER_DB.STAGING TO ROLE PIPELINE_ROLE;
GRANT USAGE ON SCHEMA WEATHER_DB.MARTS   TO ROLE PIPELINE_ROLE;
GRANT USAGE ON SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;

-- Current + future table privileges
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA WEATHER_DB.RAW   TO ROLE PIPELINE_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES  IN SCHEMA WEATHER_DB.RAW   TO ROLE PIPELINE_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA WEATHER_DB.MARTS TO ROLE PIPELINE_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES  IN SCHEMA WEATHER_DB.MARTS TO ROLE PIPELINE_ROLE;

-- dbt needs to create objects in DBT_DEV
GRANT CREATE TABLE ON SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;
GRANT CREATE VIEW  ON SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;

-- Sequences (for AUTOINCREMENT columns)
GRANT USAGE ON ALL SEQUENCES    IN SCHEMA WEATHER_DB.MARTS TO ROLE PIPELINE_ROLE;
GRANT USAGE ON FUTURE SEQUENCES IN SCHEMA WEATHER_DB.MARTS TO ROLE PIPELINE_ROLE;

-- Assign the role to your user (update if your username differs)
GRANT ROLE PIPELINE_ROLE TO USER SHELDIE1234;

-- ── 3. RAW LAYER TABLES ───────────────────────────────────────────────────────
USE SCHEMA RAW;

CREATE TABLE IF NOT EXISTS RAW_WEATHER_API (
    city            VARCHAR(100)  NOT NULL,
    country         VARCHAR(100)  NOT NULL,
    latitude        FLOAT         NOT NULL,
    longitude       FLOAT         NOT NULL,
    recorded_at     TIMESTAMP_NTZ NOT NULL,
    temperature_c   FLOAT,
    humidity_pct    FLOAT,
    windspeed_kmh   FLOAT,
    weather_code    INTEGER,
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    pipeline_run_id VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS RAW_AIR_QUALITY (
    city            VARCHAR(100)  NOT NULL,
    country         VARCHAR(100)  NOT NULL,
    latitude        FLOAT         NOT NULL,
    longitude       FLOAT         NOT NULL,
    recorded_at     TIMESTAMP_NTZ NOT NULL,
    pm2_5           FLOAT,
    uv_index        FLOAT,
    carbon_monoxide FLOAT,
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    pipeline_run_id VARCHAR(50)
);

-- Change-tracking stream for incremental loads
CREATE STREAM IF NOT EXISTS weather_changes_stream
    ON TABLE RAW_WEATHER_API
    COMMENT = 'CDC stream tracking changes to raw weather data';

-- ── 4. MARTS LAYER — DIMENSIONS ───────────────────────────────────────────────
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

-- ── 5. MARTS LAYER — FACTS ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS FACT_WEATHER_READINGS (
    reading_sk      INTEGER AUTOINCREMENT PRIMARY KEY,
    city_sk         INTEGER REFERENCES DIM_CITY(city_sk),
    date_sk         INTEGER REFERENCES DIM_DATE(date_sk),
    weather_code_sk INTEGER REFERENCES DIM_WEATHER_CODE(code_sk),
    recorded_at     TIMESTAMP_NTZ NOT NULL,
    temperature_c   FLOAT,
    humidity_pct    FLOAT,
    windspeed_kmh   FLOAT,
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    pipeline_run_id VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS FACT_AIR_QUALITY_READINGS (
    reading_sk      INTEGER AUTOINCREMENT PRIMARY KEY,
    city_sk         INTEGER REFERENCES DIM_CITY(city_sk),
    date_sk         INTEGER REFERENCES DIM_DATE(date_sk),
    recorded_at     TIMESTAMP_NTZ NOT NULL,
    pm2_5           FLOAT,
    uv_index        FLOAT,
    carbon_monoxide FLOAT,
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    pipeline_run_id VARCHAR(50)
);

-- ── 6. DIMENSION SEED DATA ────────────────────────────────────────────────────

-- Cities
INSERT INTO DIM_CITY (city_nk, city_name, state, country, latitude, longitude)
SELECT * FROM (VALUES
    ('Mumbai',    'Mumbai',    'Maharashtra', 'India', 19.07, 72.88),
    ('Bangalore', 'Bangalore', 'Karnataka',   'India', 12.97, 77.59),
    ('Delhi',     'Delhi',     'Delhi NCR',   'India', 28.70, 77.10),
    ('Chennai',   'Chennai',   'Tamil Nadu',  'India', 13.08, 80.27)
) AS v(city_nk, city_name, state, country, latitude, longitude)
WHERE NOT EXISTS (SELECT 1 FROM DIM_CITY WHERE DIM_CITY.city_nk = v.city_nk);

-- Weather codes
INSERT INTO DIM_WEATHER_CODE (code_value, description, category, severity)
SELECT * FROM (VALUES
    (0,  'Clear sky',           'Clear',        'Low'),
    (1,  'Mainly clear',        'Clear',        'Low'),
    (2,  'Partly cloudy',       'Cloudy',       'Low'),
    (3,  'Overcast',            'Cloudy',       'Low'),
    (45, 'Foggy',               'Fog',          'Medium'),
    (51, 'Light drizzle',       'Rain',         'Low'),
    (61, 'Slight rain',         'Rain',         'Medium'),
    (80, 'Slight rain showers', 'Rain',         'Medium'),
    (95, 'Thunderstorm',        'Thunderstorm', 'High')
) AS v(code_value, description, category, severity)
WHERE NOT EXISTS (SELECT 1 FROM DIM_WEATHER_CODE WHERE DIM_WEATHER_CODE.code_value = v.code_value);

-- Date dimension — 120 days from 2026-05-01
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
    FROM TABLE(GENERATOR(ROWCOUNT => 120))
) d
WHERE NOT EXISTS (
    SELECT 1 FROM DIM_DATE
    WHERE DIM_DATE.date_sk = TO_NUMBER(TO_VARCHAR(d.date_val, 'YYYYMMDD'))
);

-- ── 7. DATA VAULT (RAW schema) ────────────────────────────────────────────────
USE SCHEMA RAW;

CREATE TABLE IF NOT EXISTS HUB_CITY (
    city_hk       VARCHAR(32)   PRIMARY KEY,
    city_nk       VARCHAR(100)  NOT NULL,
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    record_source VARCHAR(100)  NOT NULL
);

CREATE TABLE IF NOT EXISTS HUB_DATE (
    date_hk       VARCHAR(32)   PRIMARY KEY,
    full_date     DATE          NOT NULL,
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    record_source VARCHAR(100)  NOT NULL
);

CREATE TABLE IF NOT EXISTS LINK_WEATHER_READING (
    reading_hk    VARCHAR(32)   PRIMARY KEY,
    city_hk       VARCHAR(32)   NOT NULL REFERENCES HUB_CITY(city_hk),
    date_hk       VARCHAR(32)   NOT NULL REFERENCES HUB_DATE(date_hk),
    recorded_at   TIMESTAMP_NTZ NOT NULL,
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    record_source VARCHAR(100)  NOT NULL
);

CREATE TABLE IF NOT EXISTS SAT_CITY_DETAILS (
    city_hk       VARCHAR(32)   NOT NULL REFERENCES HUB_CITY(city_hk),
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    load_end_date TIMESTAMP_NTZ,
    record_source VARCHAR(100)  NOT NULL,
    state         VARCHAR(100),
    country       VARCHAR(100),
    latitude      FLOAT,
    longitude     FLOAT,
    PRIMARY KEY (city_hk, load_date)
);

CREATE TABLE IF NOT EXISTS SAT_WEATHER_READINGS (
    reading_hk    VARCHAR(32)   NOT NULL REFERENCES LINK_WEATHER_READING(reading_hk),
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    load_end_date TIMESTAMP_NTZ,
    record_source VARCHAR(100)  NOT NULL,
    temperature_c FLOAT,
    humidity_pct  FLOAT,
    windspeed_kmh FLOAT,
    weather_code  INTEGER,
    PRIMARY KEY (reading_hk, load_date)
);

-- ── 8. VERIFY ─────────────────────────────────────────────────────────────────
SELECT 'DIM_CITY'         AS tbl, COUNT(*) AS cnt FROM MARTS.DIM_CITY
UNION ALL SELECT 'DIM_DATE',         COUNT(*) FROM MARTS.DIM_DATE
UNION ALL SELECT 'DIM_WEATHER_CODE', COUNT(*) FROM MARTS.DIM_WEATHER_CODE;

SHOW TABLES IN DATABASE WEATHER_DB;

-- ============================================================
-- REBUILD COMPLETE.
-- Next: update account identifier + username in .env,
-- profiles.yml, and the Airflow connection. Then run your
-- pipeline to repopulate RAW + FACT data.
-- ============================================================
