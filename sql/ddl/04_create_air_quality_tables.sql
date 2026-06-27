USE DATABASE WEATHER_DB;

-- RAW layer table for air quality data
USE SCHEMA RAW;

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

-- MARTS layer fact table for air quality
-- Shares DIM_CITY and DIM_DATE with the weather fact (conformed dimensions)
USE SCHEMA MARTS;

CREATE TABLE IF NOT EXISTS FACT_AIR_QUALITY_READINGS (
    reading_sk      INTEGER       AUTOINCREMENT PRIMARY KEY,
    city_sk         INTEGER       REFERENCES DIM_CITY(city_sk),
    date_sk         INTEGER       REFERENCES DIM_DATE(date_sk),
    recorded_at     TIMESTAMP_NTZ NOT NULL,
    pm2_5           FLOAT,
    uv_index        FLOAT,
    carbon_monoxide FLOAT,
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    pipeline_run_id VARCHAR(50)
);