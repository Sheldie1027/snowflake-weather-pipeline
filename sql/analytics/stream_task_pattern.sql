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