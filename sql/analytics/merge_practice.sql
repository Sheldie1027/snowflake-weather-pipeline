--Syntax structure:
MERGE INTO target_table AS target
USING source_data AS source
ON target.key_column = source.key_column
WHEN MATCHED THEN
    UPDATE SET target.col1 = source.col1, ...
WHEN NOT MATCHED THEN
    INSERT (col1, col2, ...) VALUES (source.col1, source.col2, ...);


USE DATABASE WEATHER_DB;
USE SCHEMA MARTS;

-- First check current state
SELECT * FROM DIM_CITY ORDER BY city_sk;

-- Simulate incoming data with one new city and one updated city
-- Kolkata is new, Mumbai has an updated state name
MERGE INTO DIM_CITY AS target
USING (SELECT 'Mumbai'    AS city_nk, 'Mumbai'    AS city_name, 
           'MH'        AS state,   'India'      AS country,
           19.07       AS latitude, 72.88       AS longitude
    UNION ALL
    SELECT 'Kolkata',  'Kolkata',  'West Bengal', 'India', 22.57, 88.36) AS source
ON target.city_nk = source.city_nk AND target.is_current = TRUE
WHEN MATCHED AND (
    target.state != source.state OR
    target.city_name != source.city_name
) THEN
    UPDATE SET
        target.state      = source.state,
        target.city_name  = source.city_name
WHEN NOT MATCHED THEN
    INSERT (city_nk, city_name, state, country, latitude, longitude, is_current)
    VALUES (
        source.city_nk, source.city_name, source.state,
        source.country, source.latitude, source.longitude, TRUE
    );

-- Check results
SELECT * FROM DIM_CITY ORDER BY city_sk;


--For Soft Delete

-- Step 1: Identify rows that need soft-deleting
SELECT city_nk, city_name, is_current
FROM DIM_CITY
WHERE is_current = TRUE
  AND city_nk NOT IN ('Mumbai', 'Bangalore', 'Delhi', 'Chennai');

-- Step 2: Soft-delete them
UPDATE DIM_CITY
SET is_current = FALSE,
    valid_to   = CURRENT_TIMESTAMP()
WHERE is_current = TRUE
  AND city_nk NOT IN ('Mumbai', 'Bangalore', 'Delhi', 'Chennai');

-- Step 3: Verify
SELECT city_nk, is_current, valid_to FROM DIM_CITY ORDER BY city_sk;

-- Step 4: For comparison, here is the full pattern - 
-- combining MERGE (for upserts) with UPDATE (for soft deletes)
-- This is what your production pipeline will look like:

-- 4a) Upsert active records
MERGE INTO DIM_CITY AS target
USING (
    SELECT 'Mumbai'    AS city_nk, 'Maharashtra' AS state UNION ALL
    SELECT 'Bangalore',              'Karnataka'         UNION ALL
    SELECT 'Delhi',                  'Delhi NCR'         UNION ALL
    SELECT 'Chennai',                'Tamil Nadu'
) AS source
ON target.city_nk = source.city_nk AND target.is_current = TRUE
WHEN MATCHED AND target.state != source.state THEN
    UPDATE SET target.state = source.state;

-- 4b) Soft-delete records not in source (separate statement)
UPDATE DIM_CITY
SET is_current = FALSE, valid_to = CURRENT_TIMESTAMP()
WHERE is_current = TRUE
  AND city_nk NOT IN ('Mumbai', 'Bangalore', 'Delhi', 'Chennai');