-- ============================================================
-- Week 1 Project: Weather Intelligence Pipeline
-- Script 01: Raw Layer Tables
-- Run as: SYSADMIN role
-- ============================================================

USE DATABASE WEATHER_DB;
USE SCHEMA RAW;

-- Stage for file-based loads
CREATE STAGE IF NOT EXISTS weather_raw_stage
    COMMENT = 'Internal stage for raw weather CSV files';

-- File format for CSV loads
CREATE FILE FORMAT IF NOT EXISTS csv_standard
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null', '')
    EMPTY_FIELD_AS_NULL = TRUE
    TRIM_SPACE = TRUE;

-- Main raw table - receives data directly from Python connector
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

-- Change tracking stream for incremental loads
CREATE STREAM IF NOT EXISTS weather_changes_stream
    ON TABLE RAW_WEATHER_API
    COMMENT = 'CDC stream tracking changes to raw weather data';