# Data Model Design Decisions

## Fact Table Grains

### FACT_WEATHER_READINGS
One row = one hourly weather reading for one city
Grain: city + hour (recorded_at timestamp)
Lowest level of detail available from Open-Meteo API

### FACT_AIR_QUALITY_READINGS (Week 2 addition)
One row = one hourly air quality reading for one city
Grain: city + hour (recorded_at timestamp)
Same grain as weather — enables joining on city_sk + date_sk + hour

## Conformed Dimensions

### DIM_CITY
Used by: FACT_WEATHER_READINGS, FACT_AIR_QUALITY_READINGS
Meaning: the same city definition in both contexts
Benefit: you can JOIN weather and air quality data on city_sk directly

### DIM_DATE  
Used by: FACT_WEATHER_READINGS, FACT_AIR_QUALITY_READINGS
Meaning: the same calendar date in both contexts
Benefit: you can compare weather vs air quality on the same date

## Junk Dimensions

### DIM_WEATHER_FLAGS
Used by :FACT_WEATHER_READINGS
Meaning: contains low cardinality flag columns that are used FACT_WEATHER_READINGS using the key flag_Sk
Benefit: one place for low cardinality columns instead of their own dimension tables

## Kimball vs Data Vault — When to Use Each

### Kimball Star Schema (my analytics layer)
Chosen for: fast analytical queries, simple joins, BI-friendly structure
Best when: the use case is known and analytics-focused
Tradeoff: less flexible if source structure changes frequently

### Data Vault (my audit/history layer)
Chosen for: full auditability, handling schema changes, multiple source systems
Best when: regulated environments, complex enterprise data, evolving sources
Tradeoff: more complex to query — usually sits between raw and marts

### My pipeline's approach
RAW (landing) → Data Vault (audit-friendly history) → Star Schema (analytics)
This hybrid gives both auditability and query performance.


### Known Improvements
Need to delete old data before inserting for the same day or use upsert instead.