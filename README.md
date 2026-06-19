# Weather Intelligence Pipeline

> End-to-end data pipeline pulling live weather data for Indian cities, 
> transforming it through a star schema in Snowflake, and generating 
> AI-powered insights using Groq LLaMA3.

## Architecture

![Architecture](docs/architecture.png)

## Data Model

![Star Schema](models/star_schema.png)

## Tech Stack

![Python](https://img.shields.io/badge/Python-3.15-blue)
![Snowflake](https://img.shields.io/badge/Snowflake-Standard-29B5E8)
![Groq](https://img.shields.io/badge/Groq-LLaMA3-orange)
![SQL](https://img.shields.io/badge/SQL-Snowflake-red)

## What It Does

1. **Extracts** hourly weather data for Mumbai, Bangalore, Delhi and Chennai 
   from the Open-Meteo free API (no key needed)
2. **Transforms** it with Python + pandas — cleaning, typing, and enriching
3. **Loads** raw data into Snowflake's RAW layer via the Python connector
4. **Models** data into a star schema (FACT_WEATHER_READINGS + 3 dimensions)
5. **Analyses** with SQL — window functions, CTEs, rolling averages
6. **Summarises** with Groq LLaMA3 — AI-generated weather intelligence report

## Project Structure
snowflake-weather-pipeline/

├── src/            # Python pipeline scripts

├── sql/

│   ├── ddl/        # Table creation scripts (run in order 01→03)

│   └── analytics/  # Analytical SQL queries

├── models/         # Data model diagrams

├── docs/           # Architecture diagrams and outputs

└── config/         # .env file (not committed)


## Setup Instructions

### Prerequisites
- Python 3.11+
- Snowflake trial account (free at snowflake.com)
- Groq API key (free at console.groq.com)

### Steps

1. Clone the repo
```bash
git clone https://github.com/YOUR_USERNAME/snowflake-weather-pipeline.git
cd snowflake-weather-pipeline
```

2. Create virtual environment
```bash
python -m venv venv
venv\Scripts\activate   # Windows
source venv/bin/activate # Mac/Linux
pip install -r requirements.txt
```

3. Set up credentials
```bash
cp config/.env.example config/.env
# Fill in your Snowflake and Groq credentials
```

4. Run Snowflake DDL scripts in order
Run `sql/ddl/01_create_raw_tables.sql` then `02` then `03` in Snowflake

5. Run the pipeline
```bash
python src/main.py
```

## Sample Output

### AI Summary
> Delhi led with peak temperatures reaching 41.5°C while Bangalore 
> remained the coolest at 27.5°C average...

### Analytics
See `sql/analytics/project_insights.sql` for 5 analytical queries 
covering daily averages, rolling means, temperature rankings, and anomaly detection.

## Data Dictionary

| Table | Column | Type | Description |
|---|---|---|---|
| FACT_WEATHER_READINGS | reading_sk | INTEGER | Surrogate primary key |
| FACT_WEATHER_READINGS | city_sk | INTEGER | FK to DIM_CITY |
| FACT_WEATHER_READINGS | temperature_c | FLOAT | Temperature in Celsius |
| DIM_CITY | is_current | BOOLEAN | SCD Type 2 current flag |
| DIM_CITY | valid_from | TIMESTAMP | SCD Type 2 effective start |