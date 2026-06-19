-- ============================================================
-- Script 03: Fact Table
-- ============================================================

USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

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