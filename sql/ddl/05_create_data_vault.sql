USE DATABASE WEATHER_DB;
USE SCHEMA RAW;

-- ── HUBS — store unique business keys ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS HUB_CITY (
    city_hk       VARCHAR(32)   PRIMARY KEY,   -- MD5 hash of city name
    city_nk       VARCHAR(100)  NOT NULL,      -- natural/business key
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    record_source VARCHAR(100)  NOT NULL
);

CREATE TABLE IF NOT EXISTS HUB_DATE (
    date_hk       VARCHAR(32)   PRIMARY KEY,   -- MD5 hash of date
    full_date     DATE          NOT NULL,
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    record_source VARCHAR(100)  NOT NULL
);

-- ── LINK — stores the relationship + grain ────────────────────────────────────

CREATE TABLE IF NOT EXISTS LINK_WEATHER_READING (
    reading_hk    VARCHAR(32)   PRIMARY KEY,   -- MD5 of city + recorded_at
    city_hk       VARCHAR(32)   NOT NULL REFERENCES HUB_CITY(city_hk),
    date_hk       VARCHAR(32)   NOT NULL REFERENCES HUB_DATE(date_hk),
    recorded_at   TIMESTAMP_NTZ NOT NULL,      -- grain identifier
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    record_source VARCHAR(100)  NOT NULL
);

-- ── SATELLITES — store descriptive attributes ─────────────────────────────────

CREATE TABLE IF NOT EXISTS SAT_CITY_DETAILS (
    city_hk       VARCHAR(32)   NOT NULL REFERENCES HUB_CITY(city_hk),
    load_date     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    load_end_date TIMESTAMP_NTZ,               -- NULL = current version
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
    load_end_date TIMESTAMP_NTZ,               -- NULL = current version
    record_source VARCHAR(100)  NOT NULL,
    temperature_c FLOAT,
    humidity_pct  FLOAT,
    windspeed_kmh FLOAT,
    weather_code  INTEGER,
    PRIMARY KEY (reading_hk, load_date)
);

-- ── LOADING THE VAULT (hash keys computed at load time) ───────────────────────

-- Load HUB_CITY
INSERT INTO HUB_CITY (city_hk, city_nk, record_source)
SELECT
    MD5(UPPER(TRIM(city))) AS city_hk,
    city                   AS city_nk,
    'open-meteo-api'       AS record_source
FROM RAW_WEATHER_API
WHERE MD5(UPPER(TRIM(city))) NOT IN (SELECT city_hk FROM HUB_CITY)
GROUP BY city;

-- Load HUB_DATE
INSERT INTO HUB_DATE (date_hk, full_date, record_source)
SELECT
    MD5(TO_VARCHAR(DATE(recorded_at), 'YYYY-MM-DD')) AS date_hk,
    DATE(recorded_at)                                AS full_date,
    'open-meteo-api'                                 AS record_source
FROM RAW_WEATHER_API
WHERE MD5(TO_VARCHAR(DATE(recorded_at), 'YYYY-MM-DD')) NOT IN (SELECT date_hk FROM HUB_DATE)
GROUP BY DATE(recorded_at);

-- Load LINK_WEATHER_READING
INSERT INTO LINK_WEATHER_READING
    (reading_hk, city_hk, date_hk, recorded_at, record_source)
SELECT
    MD5(UPPER(TRIM(city)) || '|' || TO_VARCHAR(recorded_at, 'YYYY-MM-DD HH24:MI:SS')) AS reading_hk,
    MD5(UPPER(TRIM(city)))                                                            AS city_hk,
    MD5(TO_VARCHAR(DATE(recorded_at), 'YYYY-MM-DD'))                                 AS date_hk,
    recorded_at,
    'open-meteo-api'
FROM RAW_WEATHER_API
WHERE MD5(UPPER(TRIM(city)) || '|' || TO_VARCHAR(recorded_at, 'YYYY-MM-DD HH24:MI:SS'))
    NOT IN (SELECT reading_hk FROM LINK_WEATHER_READING);

-- Load SAT_WEATHER_READINGS
INSERT INTO SAT_WEATHER_READINGS
    (reading_hk, record_source, temperature_c, humidity_pct, windspeed_kmh, weather_code)
SELECT
    MD5(UPPER(TRIM(city)) || '|' || TO_VARCHAR(recorded_at, 'YYYY-MM-DD HH24:MI:SS')) AS reading_hk,
    'open-meteo-api',
    temperature_c,
    humidity_pct,
    windspeed_kmh,
    weather_code
FROM RAW_WEATHER_API
WHERE temperature_c IS NOT NULL;

-- ── VERIFY THE VAULT JOINS CORRECTLY ──────────────────────────────────────────

SELECT
    h.city_nk AS city,
    d.full_date,
    l.recorded_at,
    s.temperature_c,
    s.humidity_pct,
    s.windspeed_kmh
FROM LINK_WEATHER_READING l
JOIN HUB_CITY h            ON l.city_hk    = h.city_hk
JOIN HUB_DATE d            ON l.date_hk    = d.date_hk
JOIN SAT_WEATHER_READINGS s ON l.reading_hk = s.reading_hk
WHERE s.load_end_date IS NULL
ORDER BY d.full_date, h.city_nk
LIMIT 20;