# Weather Intelligence Pipeline

![dbt CI](https://github.com/Sheldie1027/snowflake-weather-pipeline/actions/workflows/dbt_ci.yml/badge.svg)
![Snowflake](https://img.shields.io/badge/Snowflake-Data%20Warehouse-29B5E8)
![Airflow](https://img.shields.io/badge/Apache%20Airflow-Orchestration-017CEE)
![dbt](https://img.shields.io/badge/dbt-Core-FF694B)
![Docker](https://img.shields.io/badge/Docker-Containerised-2496ED)
![Python](https://img.shields.io/badge/Python-3.11-3776AB)
![License](https://img.shields.io/badge/License-MIT-green)

A production-shaped **ELT + AI pipeline** that ingests weather and air quality data
for Indian cities, transforms it inside Snowflake with dbt, and generates an
AI-written intelligence report. Built to demonstrate modern data engineering
practice end to end — orchestration, testing, CI/CD, environment separation,
alerting, and LLM integration — at zero infrastructure cost.

**Data source:** [Open-Meteo](https://open-meteo.com/) Weather + Air Quality APIs (free, no key)

---

## What this demonstrates

- **ELT architecture** — Python extracts and loads raw data; dbt transforms it in-warehouse
- **Medallion layering** — RAW (Bronze) → dbt staging/intermediate views (Silver) → dbt marts (Gold)
- **Orchestration** — Apache Airflow in Docker, running the full pipeline on a schedule
- **Dimensional modelling** — a Kimball star schema plus a parallel Data Vault 2.0 layer
- **Data quality** — a layered dbt test suite that fails the pipeline before bad data reaches consumers
- **CI/CD** — GitHub Actions runs `dbt build` on every pull request; `main` is protected by a required status check
- **Environment separation** — isolated dev / CI / prod schemas selected by dbt targets
- **Alerting** — failure callbacks that name the specific failing dbt test
- **AI integration** — a resilient, provider-agnostic LLM layer producing both prose and structured JSON reports

---

## Architecture

```
+---------------------------------------------------------------+
|                    Apache Airflow (Docker)                    |
|    weather_pipeline_dag  --triggers-->  dbt_transform_dag     |
|              (failure callbacks -> email alerts)              |
+----------------------------+----------------------------------+
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
              |  Python  (extract + load)   |   E + L
              +--------------+--------------+
                             v
              +-----------------------------+
              |  Snowflake RAW  (BRONZE)    |
              +--------------+--------------+
                             v
              +-----------------------------------------+
              |  dbt  (isolated venv in Airflow image)  |   T
              |   staging + intermediate  -> SILVER     |
              |   marts                   -> GOLD       |
              |   + tests + snapshots + freshness       |
              +--------------+--------------------------+
                             v
              +-----------------------------+
              |  mart_city_daily_summary    |
              +--------------+--------------+
                             v
              +-----------------------------+
              |  LLM  -  AI Report          |
              |  (Groq; provider-agnostic)  |
              +-----------------------------+

   CI: every pull request runs dbt build against an isolated DBT_CI schema
```

![Architecture](docs/architecture.png)

---

## Tech stack

| Layer | Technology |
|---|---|
| Ingestion | Python (requests, pandas) |
| Warehouse | Snowflake |
| Transformation | dbt Core + dbt-snowflake |
| Orchestration | Apache Airflow (Docker Compose, custom image) |
| CI/CD | GitHub Actions |
| Data quality | dbt tests, dbt_utils, dbt_expectations, source freshness |
| AI layer | Groq (LLaMA 3.1 8B Instant), provider-agnostic interface |
| Resilience | tenacity (exponential backoff) |
| Auth | Snowflake key-pair (RSA) authentication |

---

## Why ELT, not ETL

Raw API responses land in Snowflake untouched, preserving the source of truth.
All transformation then happens **inside** the warehouse as version-controlled dbt
SQL — so logic is testable, documented, and re-runnable against the original data.
Python does extract and load; dbt does transform.

1. **Extract + Load** — Airflow triggers Python tasks that pull from the Open-Meteo
   APIs and load raw rows into Snowflake's `RAW` schema, stamping each with `loaded_at`.
2. **Transform** — the ingestion DAG triggers the dbt DAG, which checks source
   freshness, then cleans, dedups, models, and tests the data through to the marts.
3. **Serve** — an LLM reads the final `mart_city_daily_summary` and writes a
   natural-language intelligence report.

---

## Transformation (dbt)

### Model layers

| Medallion | Layer | Models | Materialization |
|---|---|---|---|
| Bronze | Raw | (loaded by Python) | table |
| Silver | Staging | stg_weather, stg_air_quality | view |
| Silver | Intermediate | int_daily_weather | view |
| Gold | Marts | dim_city, fct_weather_readings, fct_air_quality_readings, mart_city_daily_summary | table / incremental |

### Key features

- **Staging** deduplicates and cleans raw data (`row_number()` over city + timestamp)
- **Incremental fact models** with `merge` strategy — re-running never duplicates rows
- **Snapshots** implement SCD Type 2 automatically for the city dimension
- **Surrogate keys** via `dbt_utils.generate_surrogate_key`
- **Tests** — built-in (`unique`, `not_null`, `relationships`, `accepted_values`),
  custom singular tests, `dbt_expectations` range and row-count assertions, and
  `dbt_utils.unique_combination_of_columns` to enforce grain
- **Source freshness** runs first in the DAG — if raw data is stale, the pipeline
  fails before burning compute on it
- **Documentation & lineage** — auto-generated catalogue with a full DAG from source to AI report
- **Exposures** document the AI report as a downstream consumer

### Data modelling

The **star schema** (`dim_city`, `fct_weather_readings`) is the flexible analytical
core — dimensions can be recombined with any fact. The **serving layer**
(`mart_city_daily_summary`) is a wide, pre-joined table — effectively a One Big
Table — because it feeds a known consumer that shouldn't need to know the join keys.
Star schema for modelling, OBT for serving.

`fct_weather_readings` is a **transaction fact** (one immutable row per hourly
reading). `mart_city_daily_summary` is a **periodic snapshot fact** (one row per
city per day). `pipeline_run_id` on the fact is a **degenerate dimension** — an
identifier with no descriptive attributes to warrant its own table.

### Data lineage

![dbt lineage](docs/dbt_lineage.png)

---

## CI/CD

Every pull request triggers a GitHub Actions workflow that:

1. Spins up a clean Ubuntu runner
2. Installs dbt and decodes the Snowflake key from an encrypted secret
3. Runs `dbt build` against an **isolated `DBT_CI` schema** — so CI can never
   clobber dev or prod
4. Reports pass/fail on the PR

`main` is protected by a **required status check**: broken SQL or a failing data
test cannot be merged. Credentials are supplied via GitHub Secrets and never
appear in the repository.

---

## Environments

| Environment | Schema | Written by | Purpose |
|---|---|---|---|
| dev | `DBT_DEV` | Developer, interactively | Experiment freely |
| ci | `DBT_CI` | GitHub Actions | Verify a PR; throwaway |
| prod | `DBT_PROD` | Airflow, on schedule | What consumers read |

Environments are selected at runtime with dbt **targets** — the same code, a
different destination. **Only the orchestrator writes to prod**; production is
built by an automated, reproducible process from committed code.

---

## The AI layer

The report generator is deliberately **provider-agnostic** (`src/llm_provider.py`):
the report logic imports no vendor SDK, so swapping models is a drop-in.

**Production model: Groq (llama-3.1-8b-instant)** — free, sub-second, and with an
engineered prompt it produces faithful reports. See
[`docs/llm_comparison.md`](docs/llm_comparison.md) for the reasoned comparison.

**Reliability features:**

- **Engineered prompts** with explicit anti-hallucination guards ("use ONLY the
  numbers provided") and anti-back-fill rules ("report ONLY cities present in the data")
- **Few-shot examples** using fictional cities, so example values can never leak
  into a real report
- **Structured JSON output** with defensive parsing (fence-stripping, type
  checking, safe fallback) and shape validation
- **Retries with exponential backoff** (tenacity), scoped to transient errors only —
  rate limits and 5xx retry; auth and bad-request failures fail fast
- **Observability** — per-call latency, token estimates, output size, and error
  type are logged on every call
- **Token guards** — the data payload is estimated and capped so the pipeline
  degrades gracefully rather than blowing the context window as data grows

The AI never reads raw data. It reads `mart_city_daily_summary` — a tested,
documented dbt mart — so every value it sees has passed the full test suite.

---

## Alerting

Airflow failure callbacks send an email naming the DAG, task, retry count,
exception, and a direct link to the log. For dbt tasks, the alert parses
`run_results.json` to name the **specific failing model or test** — so an alert
reads "unique_reading_sk failed: 3 duplicate values" rather than "dbt_test failed."

Alert code is wrapped in try/except: a failure in the alerting system can never
mask the original failure it is reporting.

---

## Project structure

```
snowflake-weather-pipeline/
+-- .github/workflows/
|   +-- dbt_ci.yml                      # CI: dbt build on every PR
+-- airflow/
|   +-- dags/
|   |   +-- weather_pipeline_dag.py     # ingestion + AI
|   |   +-- dbt_transform_dag.py        # freshness -> run -> test
|   |   +-- alerts.py                   # failure callbacks
|   |   +-- dbt_results.py              # parses run_results.json
|   +-- Dockerfile                      # bakes dbt into the Airflow image
|   +-- docker-compose.yaml
+-- dbt/weather_dbt/
|   +-- models/
|   |   +-- staging/                    # stg_ views, sources, freshness
|   |   +-- intermediate/               # int_ views
|   |   +-- marts/                      # dim_, fct_, mart_
|   |   +-- exposures.yml
|   +-- snapshots/                      # SCD2 city snapshot
|   +-- seeds/  macros/  packages.yml
|   +-- ci_profiles.yml                 # CI connection (no secrets)
+-- src/
|   +-- main.py                         # weather extract + load
|   +-- load_air_quality.py             # air quality extract + load
|   +-- ai_summary.py                   # report generation
|   +-- llm_provider.py                 # provider-agnostic LLM interface
|   +-- groq_client.py                  # Groq + retries
|   +-- snowflake_client.py
+-- sql/ddl/  sql/analytics/
+-- docs/                               # architecture, lineage, notes, comparison
+-- config/                             # .env, RSA keys (gitignored)
```

---

## Getting started

**Prerequisites:** Snowflake account, Python 3.11+, Docker Desktop, a Groq API key (free tier).

```bash
git clone https://github.com/Sheldie1027/snowflake-weather-pipeline.git
cd snowflake-weather-pipeline
python -m venv venv && venv\Scripts\activate      # Windows
pip install -r requirements.txt
```

1. **Credentials** — create `config/.env` with your Snowflake account, user,
   key path, and Groq API key. Generate an RSA key pair and register the public
   key on your Snowflake user.
2. **Warehouse** — run `sql/ddl/00_full_rebuild.sql` in Snowsight.
3. **Load** — `python src/main.py && python src/load_air_quality.py`
4. **Transform** — `cd dbt/weather_dbt && dbt deps && dbt build`
5. **Orchestrate** — `cd airflow && docker compose build && docker compose up -d`,
   then trigger `weather_pipeline_dag` at `localhost:8080`
6. **Report** — `python src/ai_summary.py`

---

## Roadmap

- [x] Week 1 — Snowflake, Python ingestion, star schema, LLM summaries
- [x] Week 2 — Airflow orchestration, air quality data, Data Vault 2.0
- [x] Week 3 — dbt transformations, testing, documentation, lineage
- [x] Week 4 — Prompt engineering, structured output, resilience, CI/CD, dev/prod separation, alerting
- [ ] Week 5 — Backfills, data completeness testing, performance and cost analysis

---

## License

MIT — see [LICENSE](LICENSE).

---

*Built by Sheldon Monteiro as a portfolio project demonstrating end-to-end data
engineering: ingestion, warehousing, dimensional modelling, orchestration,
transformation, testing, CI/CD, alerting, and AI integration.*
