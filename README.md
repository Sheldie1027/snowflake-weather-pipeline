# Weather Intelligence Pipeline

![Snowflake](https://img.shields.io/badge/Snowflake-Data%20Warehouse-29B5E8)
![Airflow](https://img.shields.io/badge/Apache%20Airflow-Orchestration-017CEE)
![dbt](https://img.shields.io/badge/dbt-Core-FF694B)
![dbt CI](https://github.com/Sheldie1027/snowflake-weather-pipeline/actions/workflows/dbt_ci.yml/badge.svg)
![Python](https://img.shields.io/badge/Python-ETL-3776AB)
![License](https://img.shields.io/badge/License-MIT-green)


An end-to-end, production-shaped **ELT + AI pipeline** that ingests weather and
air quality data for four Indian cities, transforms it inside Snowflake with dbt,
and generates an AI-written intelligence report. Built from scratch to demonstrate
modern data engineering practices — orchestration, testing, documentation, and
lineage — at zero infrastructure cost.

**Cities tracked:** Mumbai · Bangalore · Delhi · Chennai
**Data source:** [Open-Meteo](https://open-meteo.com/) Weather + Air Quality APIs (free, no key)

---

## What this project demonstrates

- **Modern ELT architecture** — extract/load with Python, transform in-warehouse with dbt
- **Orchestration** — Apache Airflow (Docker) running the full pipeline on a schedule
- **Dimensional modelling** — a Kimball star schema plus a Data Vault 2.0 layer
- **Data quality** — a layered dbt testing suite that fails the pipeline on bad data
- **Documentation & lineage** — auto-generated dbt docs with a full source-to-AI DAG
- **AI integration** — an LLM-generated weather intelligence report reading from tested marts

---

## Architecture

```
+-------------------------------------------------------------+
|                  Apache Airflow (Docker)                    |
|   weather_pipeline_dag  --triggers-->  dbt_transform_dag    |
+----------------------------+--------------------------------+
                             |
         +-------------------+-------------------+
         v                                       v
+------------------+                    +------------------+
| Open-Meteo       |                    | Open-Meteo       |
| Weather API      |                    | Air Quality API  |
+--------+---------+                    +--------+---------+
         |                                       |
         +-------------------+-------------------+
                             v
              +-----------------------------+
              |  Python  (extract + load)   |
              +--------------+--------------+
                             v
              +-----------------------------+
              |  Snowflake  -  RAW schema   |
              +--------------+--------------+
                             v
              +-----------------------------------------+
              |  dbt  (isolated venv in Airflow image)  |
              |   staging -> intermediate -> marts      |
              |   + tests + snapshots + docs            |
              +--------------+--------------------------+
                             v
              +-----------------------------+
              |  mart_city_daily_summary    |
              +--------------+--------------+
                             v
              +-----------------------------+
              |  Groq LLaMA  -  AI Report   |
              +-----------------------------+
```

![Architecture](docs/architecture.png)

---

## Tech stack

| Layer | Technology |
|---|---|
| Ingestion | Python (requests, pandas) |
| Warehouse | Snowflake |
| Transformation | dbt Core + dbt-snowflake |
| Orchestration | Apache Airflow (Docker Compose) |
| Data quality | dbt tests, dbt_utils, dbt_expectations |
| AI summary | Groq (LLaMA 3.1 8B Instant) |
| Auth | Snowflake key-pair (RSA) authentication |

---

## Data flow (ELT)

This pipeline deliberately follows **ELT**, not ETL. Raw API responses land in
Snowflake untouched (the `RAW` schema), preserving the source of truth. All
transformation then happens *inside* Snowflake as version-controlled dbt SQL —
so logic is testable, documented, and re-runnable against the original data.

1. **Extract + Load** — Airflow triggers Python tasks that pull from the Open-Meteo
   Weather and Air Quality APIs and load raw rows into Snowflake `RAW` tables,
   stamping each with a `loaded_at` timestamp.
2. **Transform** — the ingestion DAG triggers the dbt DAG, which cleans, dedups,
   models, and tests the data through staging and marts.
3. **Serve** — a Groq LLaMA model reads the final `mart_city_daily_summary` and
   writes a natural-language intelligence report.

---

## Transformation (dbt)

The transformation layer is built with dbt Core. Python extracts and loads raw
data; dbt transforms it inside Snowflake using tested, version-controlled SQL models.

### Model layers

| Layer | Models | Materialization |
|---|---|---|
| Staging | stg_weather, stg_air_quality | view |
| Intermediate | int_daily_weather | view |
| Marts | dim_city, fct_weather_readings, fct_air_quality_readings, mart_city_daily_summary | table / incremental |

### Key features

- **Staging layer** deduplicates and cleans raw data (`row_number()` over city + timestamp)
- **Incremental fact models** with `merge` strategy for idempotent loads — re-running never duplicates rows
- **Snapshots** implement Slowly Changing Dimension Type 2 automatically for the city dimension
- **Surrogate keys** via `dbt_utils.generate_surrogate_key`
- **Data tests** — built-in (`unique`, `not_null`, `relationships`, `accepted_values`),
  custom singular tests, plus `dbt_expectations` range and row-count assertions
- **Source freshness** monitoring to detect a stalled pipeline
- **Documentation & lineage** — an auto-generated catalogue with a full DAG from source to AI report
- **Exposures** document the AI report as a downstream consumer

### Analytics mart feeding the AI

`mart_city_daily_summary` combines weather and air quality per city per day,
deriving an air quality category (Good / Moderate / Unhealthy). This tested,
documented mart is the single clean input the AI summary reads from — so the
LLM never sees unvalidated data.

### dbt + Airflow

dbt runs in an isolated virtualenv baked into a custom Airflow Docker image,
keeping its dependencies fully separate from Airflow's own environment. The
ingestion DAG triggers the dbt DAG via `TriggerDagRunOperator`, so the complete
ELT flow is orchestrated end to end.

### Data lineage

![dbt lineage](docs/dbt_lineage.png)

---

## Data modelling

### Star schema (Kimball)

- `dim_city` — city dimension (with SCD Type 2 history via dbt snapshot)
- `dim_date` — date dimension
- `dim_weather_code` — weather condition lookup
- `fct_weather_readings` — hourly weather facts (incremental)
- `fct_air_quality_readings` — hourly air quality facts (incremental)

### Data Vault 2.0

A parallel Data Vault layer (hubs, links, satellites) demonstrates an
alternative, highly auditable modelling approach alongside the star schema.

---

## Project structure

```
snowflake-weather-pipeline/
+-- airflow/
|   +-- dags/
|   |   +-- weather_pipeline_dag.py     # ingestion + AI
|   |   +-- dbt_transform_dag.py        # dbt run + test
|   |   +-- learning/                   # progression / learning DAGs
|   +-- Dockerfile                      # bakes dbt into the Airflow image
|   +-- docker-compose.yaml
+-- dbt/
|   +-- weather_dbt/
|       +-- models/
|       |   +-- staging/                # stg_ views + sources + tests
|       |   +-- intermediate/           # int_ views
|       |   +-- marts/                  # dim_, fct_, mart_ + tests
|       |   +-- exposures.yml           # AI report as a consumer
|       +-- snapshots/                  # SCD2 city snapshot
|       +-- seeds/                      # weather_codes.csv
|       +-- macros/                     # celsius_to_fahrenheit, etc.
|       +-- packages.yml                # dbt_utils, dbt_expectations
+-- src/
|   +-- main.py                         # weather extract + load
|   +-- load_air_quality.py             # air quality extract + load
|   +-- ai_summary.py                   # Groq AI report (reads the mart)
+-- sql/
|   +-- ddl/                            # schema + rebuild scripts
|   +-- analytics/                      # analytical queries
+-- docs/                               # architecture + lineage images, notes
+-- config/                             # .env, RSA keys (gitignored)
+-- README.md
+-- LICENSE
```

---

## Getting started

### Prerequisites

- A Snowflake account
- Python 3.11+
- Docker Desktop (for Airflow)
- A Groq API key (free tier)

### Setup

1. **Clone and install**
   ```bash
   git clone https://github.com/Sheldie1027/snowflake-weather-pipeline.git
   cd snowflake-weather-pipeline
   python -m venv venv
   venv\Scripts\activate        # Windows
   pip install -r requirements.txt
   ```

2. **Configure credentials** — create `config/.env` with your Snowflake account,
   user, key-pair path, and Groq API key. Generate an RSA key pair and register
   the public key on your Snowflake user for key-pair authentication.

3. **Build the warehouse** — run `sql/ddl/00_full_rebuild.sql` in Snowsight to
   create the database, schemas, role, and tables.

4. **Load data**
   ```bash
   python src/main.py
   python src/load_air_quality.py
   ```

5. **Run dbt**
   ```bash
   cd dbt/weather_dbt
   dbt deps
   dbt build          # runs models, tests, seeds, snapshots
   dbt docs generate  # build the documentation site
   ```

6. **Orchestrate with Airflow**
   ```bash
   cd airflow
   docker compose build     # builds the custom image with dbt baked in
   docker compose up -d
   ```
   Open `localhost:8080` and trigger `weather_pipeline_dag`.

7. **Generate the AI report**
   ```bash
   python src/ai_summary.py
   ```

---

## Data quality

Every run is validated by a layered test suite. If the API returns a bad value —
an impossible temperature, a negative particulate reading, a duplicated grain —
the pipeline **fails before that data reaches the marts or the AI**.

- Built-in: `unique`, `not_null`, `relationships`, `accepted_values`
- Singular: custom SQL assertions (e.g. temperature within a physical range)
- dbt_expectations: value-range and row-count assertions
- dbt_utils: `unique_combination_of_columns` to enforce grain
- Source freshness: warns at 24h, errors at 48h since last load

---

## Roadmap

- [x] Week 1 — Snowflake, Python ETL, star schema, Groq AI summaries
- [x] Week 2 — Airflow orchestration, air quality data, Data Vault 2.0
- [x] Week 3 — dbt transformations, testing, documentation, lineage
- [ ] Week 4 — LLM output comparison & prompt engineering (Groq remains the production model)
- [ ] Week 5 — final polish

---

## License

MIT — see [LICENSE](LICENSE).

---

*Built by Sheldon Monteiro as a portfolio project demonstrating end-to-end data
engineering: ingestion, warehousing, dimensional modelling, orchestration,
transformation, testing, and AI integration.*
