USE ROLE ACCOUNTADMIN;
USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

-- Create a summary table that a Task will keep updated
CREATE TABLE IF NOT EXISTS DAILY_CITY_SUMMARY (
    summary_date    DATE,
    city_name       VARCHAR(100),
    avg_temp        FLOAT,
    avg_humidity    FLOAT,
    reading_count   INTEGER,
    refreshed_at    TIMESTAMP_NTZ
);

-- Create a Task that refreshes this summary table on a schedule
CREATE OR REPLACE TASK refresh_daily_summary
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '60 MINUTE'      -- runs every 60 minutes
AS
    INSERT INTO DAILY_CITY_SUMMARY
    SELECT
        DATE(f.recorded_at)             AS summary_date,
        c.city_name,
        ROUND(AVG(f.temperature_c), 2)  AS avg_temp,
        ROUND(AVG(f.humidity_pct), 2)   AS avg_humidity,
        COUNT(*)                        AS reading_count,
        CURRENT_TIMESTAMP()             AS refreshed_at
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
    GROUP BY DATE(f.recorded_at), c.city_name;


-- Tasks start suspended. Resume to activate the schedule.
ALTER TASK refresh_daily_summary RESUME;

-- Check task status
SHOW TASKS;

-- To manually run it once right now (without waiting for schedule):
EXECUTE TASK refresh_daily_summary;

SELECT * FROM DAILY_CITY_SUMMARY ORDER BY refreshed_at DESC LIMIT 10;


USE ROLE ACCOUNTADMIN;
USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

-- Root task: runs on schedule
CREATE OR REPLACE TASK task_step1_log_start
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '120 MINUTE'
AS
    INSERT INTO DAILY_CITY_SUMMARY (summary_date, city_name, refreshed_at)
    VALUES (CURRENT_DATE(), 'PIPELINE_START_MARKER', CURRENT_TIMESTAMP());

-- Child task: runs AFTER the root task completes
CREATE OR REPLACE TASK task_step2_refresh
    WAREHOUSE = COMPUTE_WH
    AFTER task_step1_log_start      -- this is the dependency
AS
    INSERT INTO DAILY_CITY_SUMMARY
    SELECT
        DATE(f.recorded_at),
        c.city_name,
        ROUND(AVG(f.temperature_c), 2),
        ROUND(AVG(f.humidity_pct), 2),
        COUNT(*),
        CURRENT_TIMESTAMP()
    FROM FACT_WEATHER_READINGS f
    JOIN DIM_CITY c ON f.city_sk = c.city_sk AND c.is_current = TRUE
    GROUP BY DATE(f.recorded_at), c.city_name;

-- IMPORTANT: when resuming chained tasks, resume children FIRST, then the root
ALTER TASK task_step2_refresh RESUME;
ALTER TASK task_step1_log_start RESUME;


-- See the execution history of your tasks
SELECT
    name,
    state,
    scheduled_time,
    completed_time,
    error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
ORDER BY scheduled_time DESC
LIMIT 20;


ALTER TASK refresh_daily_summary SUSPEND;
ALTER TASK task_step1_log_start SUSPEND;
ALTER TASK task_step2_refresh SUSPEND;

-- Verify all are suspended
SHOW TASKS;