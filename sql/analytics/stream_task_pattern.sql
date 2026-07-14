-- NOTE: These queries target the original hand-built star schema in
-- WEATHER_DB.MARTS (Weeks 1-2), which has been superseded by the dbt models
-- in WEATHER_DB.DBT_PROD. Kept as a record of the SQL techniques used.

-- A task that only processes NEW rows from the stream
CREATE OR REPLACE TASK incremental_fact_load
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '60 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('weather_changes_stream')  -- only run if there's new data
AS
    INSERT INTO MARTS.FACT_WEATHER_READINGS (city_sk, date_sk, recorded_at, temperature_c)
    SELECT
        c.city_sk,
        TO_NUMBER(TO_VARCHAR(DATE(s.recorded_at), 'YYYYMMDD')),
        s.recorded_at,
        s.temperature_c
    FROM weather_changes_stream s
    JOIN MARTS.DIM_CITY c ON s.city = c.city_nk AND c.is_current = TRUE
    WHERE s.METADATA$ACTION = 'INSERT';