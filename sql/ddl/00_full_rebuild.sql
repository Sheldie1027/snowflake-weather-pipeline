/* ============================================================================
   WEATHER INTELLIGENCE PIPELINE - FULL ENVIRONMENT REBUILD
   ============================================================================

   This script rebuilds the BASE environment only:
     - Warehouse, database, schemas
     - The PIPELINE_ROLE and its grants
     - The RAW landing tables that the Python ingestion loads into

   Everything downstream - staging, intermediate, dimensions, facts, marts,
   snapshots, seeds - is built by dbt. After running this script, run:

       cd dbt/weather_dbt
       dbt deps
       dbt seed  --target prod
       dbt build --target prod

   ARCHITECTURE (ELT / Medallion):
     RAW       (Bronze)  <- Python extract + load
     DBT_*     (Silver)  <- dbt staging + intermediate views
     DBT_*     (Gold)    <- dbt marts (dim_, fct_, mart_)

   ENVIRONMENTS:
     DBT_DEV   - developer, interactive
     DBT_CI    - GitHub Actions, throwaway, isolated from dev and prod
     DBT_PROD  - built ONLY by Airflow; what consumers read

   NOTE: The original hand-built star schema in WEATHER_DB.MARTS and the
   staging tables in WEATHER_DB.STAGING were superseded by dbt and have been
   dropped. Their DDL is retained in sql/ddl/ as a record of the earlier design.
   ============================================================================ */


/* ----------------------------------------------------------------------------
   1. WAREHOUSE
   -------------------------------------------------------------------------- */
USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND   = 60          -- suspend after 60s idle; pay only while querying
    AUTO_RESUME    = TRUE
    INITIALLY_SUSPENDED = TRUE;

ALTER WAREHOUSE COMPUTE_WH SET
    AUTO_SUSPEND = 60
    AUTO_RESUME  = TRUE;


/* ----------------------------------------------------------------------------
   2. DATABASE & SCHEMAS
   -------------------------------------------------------------------------- */
CREATE DATABASE IF NOT EXISTS WEATHER_DB;

USE DATABASE WEATHER_DB;

-- Bronze: raw landing zone, loaded by Python. Never transformed in place.
CREATE SCHEMA IF NOT EXISTS WEATHER_DB.RAW;

-- Silver + Gold: all dbt-built models. One schema per environment.
CREATE SCHEMA IF NOT EXISTS WEATHER_DB.DBT_DEV;
CREATE SCHEMA IF NOT EXISTS WEATHER_DB.DBT_CI;
CREATE SCHEMA IF NOT EXISTS WEATHER_DB.DBT_PROD;


/* ----------------------------------------------------------------------------
   3. ROLE (least privilege - the pipeline never runs as ACCOUNTADMIN)
   -------------------------------------------------------------------------- */
CREATE ROLE IF NOT EXISTS PIPELINE_ROLE;

GRANT ROLE PIPELINE_ROLE TO ROLE SYSADMIN;
GRANT ROLE PIPELINE_ROLE TO USER SHELDIE1234;

GRANT USAGE, OPERATE ON WAREHOUSE COMPUTE_WH TO ROLE PIPELINE_ROLE;
GRANT USAGE ON DATABASE WEATHER_DB TO ROLE PIPELINE_ROLE;


/* ----------------------------------------------------------------------------
   4. GRANTS
   -------------------------------------------------------------------------- */

-- RAW: Python writes here, dbt reads from here.
GRANT USAGE ON SCHEMA WEATHER_DB.RAW TO ROLE PIPELINE_ROLE;
GRANT CREATE TABLE ON SCHEMA WEATHER_DB.RAW TO ROLE PIPELINE_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA WEATHER_DB.RAW TO ROLE PIPELINE_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA WEATHER_DB.RAW TO ROLE PIPELINE_ROLE;

-- DBT_DEV: developer environment.
GRANT ALL ON SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;
GRANT ALL ON ALL TABLES    IN SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;
GRANT ALL ON ALL VIEWS     IN SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;
GRANT ALL ON FUTURE VIEWS  IN SCHEMA WEATHER_DB.DBT_DEV TO ROLE PIPELINE_ROLE;

-- DBT_CI: GitHub Actions builds here on every pull request. Throwaway.
GRANT ALL ON SCHEMA WEATHER_DB.DBT_CI TO ROLE PIPELINE_ROLE;
GRANT ALL ON ALL TABLES    IN SCHEMA WEATHER_DB.DBT_CI TO ROLE PIPELINE_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA WEATHER_DB.DBT_CI TO ROLE PIPELINE_ROLE;
GRANT ALL ON ALL VIEWS     IN SCHEMA WEATHER_DB.DBT_CI TO ROLE PIPELINE_ROLE;
GRANT ALL ON FUTURE VIEWS  IN SCHEMA WEATHER_DB.DBT_CI TO ROLE PIPELINE_ROLE;

-- DBT_PROD: written ONLY by Airflow. What the AI report reads.
GRANT ALL ON SCHEMA WEATHER_DB.DBT_PROD TO ROLE PIPELINE_ROLE;
GRANT ALL ON ALL TABLES    IN SCHEMA WEATHER_DB.DBT_PROD TO ROLE PIPELINE_ROLE;
GRANT ALL ON FUTURE TABLES IN SCHEMA WEATHER_DB.DBT_PROD TO ROLE PIPELINE_ROLE;
GRANT ALL ON ALL VIEWS     IN SCHEMA WEATHER_DB.DBT_PROD TO ROLE PIPELINE_ROLE;
GRANT ALL ON FUTURE VIEWS  IN SCHEMA WEATHER_DB.DBT_PROD TO ROLE PIPELINE_ROLE;


/* ----------------------------------------------------------------------------
   5. RAW LANDING TABLES  (Bronze)

   These are the only tables this script creates. They are append-only: every
   pipeline run inserts the API's response as-is, stamped with loaded_at and
   pipeline_run_id. Duplicates across runs are EXPECTED here - the ingestion
   re-fetches a rolling window - and are deduplicated downstream in dbt staging
   via row_number() over (city, recorded_at).
   -------------------------------------------------------------------------- */
USE ROLE PIPELINE_ROLE;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA WEATHER_DB.RAW;

CREATE TABLE IF NOT EXISTS RAW_WEATHER_API (
    CITY              VARCHAR(100),
    COUNTRY           VARCHAR(100),
    LATITUDE          FLOAT,
    LONGITUDE         FLOAT,
    RECORDED_AT       TIMESTAMP_NTZ,
    TEMPERATURE_C     FLOAT,
    HUMIDITY_PCT      FLOAT,
    WINDSPEED_KMH     FLOAT,
    WEATHER_CODE      NUMBER(38,0),
    LOADED_AT         TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    PIPELINE_RUN_ID   VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS RAW_AIR_QUALITY (
    CITY              VARCHAR(100),
    COUNTRY           VARCHAR(100),
    LATITUDE          FLOAT,
    LONGITUDE         FLOAT,
    RECORDED_AT       TIMESTAMP_NTZ,
    PM2_5             FLOAT,
    UV_INDEX          FLOAT,
    CARBON_MONOXIDE   FLOAT,
    LOADED_AT         TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    PIPELINE_RUN_ID   VARCHAR(50)
);


/* ----------------------------------------------------------------------------
   6. VERIFY
   -------------------------------------------------------------------------- */
SHOW SCHEMAS IN DATABASE WEATHER_DB;
SHOW TABLES IN SCHEMA WEATHER_DB.RAW;

SELECT 'raw_weather' AS table_name, COUNT(*) AS row_count FROM WEATHER_DB.RAW.RAW_WEATHER_API
UNION ALL
SELECT 'raw_air_quality', COUNT(*) FROM WEATHER_DB.RAW.RAW_AIR_QUALITY;


/* ============================================================================
   NEXT STEPS
   ============================================================================

   1. Load raw data:
        python src/main.py
        python src/load_air_quality.py

   2. Build the dbt model layer (seeds, staging, marts, snapshots, tests):
        cd dbt/weather_dbt
        dbt deps
        dbt seed  --target prod
        dbt build --target prod

   3. Generate the AI report:
        python src/ai_summary.py

   Or run everything through Airflow:
        cd airflow && docker compose up -d
        trigger weather_pipeline_dag at localhost:8080
   ============================================================================ */
