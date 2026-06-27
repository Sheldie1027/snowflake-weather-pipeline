# Weather Intelligence Pipeline

> An end-to-end data engineering pipeline that ingests live weather and air quality data
> for major Indian cities, models it into a Snowflake star schema (and a parallel Data Vault),
> orchestrates the whole flow with Apache Airflow, and generates AI-powered summaries using
> the Groq LLaMA API.

![Python](https://img.shields.io/badge/Python-3.13-blue)
![Snowflake](https://img.shields.io/badge/Snowflake-Standard-29B5E8)
![Airflow](https://img.shields.io/badge/Apache%20Airflow-Docker-017CEE)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED)
![Groq](https://img.shields.io/badge/Groq-LLaMA%203.1-orange)
![SQL](https://img.shields.io/badge/SQL-Snowflake-red)

---

## Overview

This project pulls hourly weather and air quality data from the free Open-Meteo APIs for
Mumbai, Bangalore, Delhi, and Chennai. The data flows through a layered Snowflake warehouse,
is transformed into an analytics-ready star schema, and is automatically orchestrated by two
Apache Airflow DAGs running on a daily schedule. A Groq-hosted LLM generates a natural-language
intelligence report from the modelled data.

The project demonstrates the full data engineering lifecycle: ingestion, transformation,
dimensional modelling, Data Vault modelling, orchestration, AI integration, and role-based
access control — all built with free tooling and no incurred costs.

---

## Architecture

```
                          ┌─────────────────────────────────────────┐
                          │         Apache Airflow (Docker)          │
                          │   weather_pipeline_dag (daily 7am IST)   │
                          │   air_quality_pipeline_dag (daily 7am)   │
                          └────────────────────┬────────────────────┘
                                               │ orchestrates
        ┌──────────────────────────────────────┼──────────────────────────────────────┐
        ▼                                       ▼                                       ▼
┌───────────────┐   HTTP/JSON   ┌──────────────────────────┐   write_pandas   ┌──────────────────┐
│ Open-Meteo    │ ────────────▶ │  Python (requests +      │ ───────────────▶ │ Snowflake RAW    │
│ Weather API   │               │  pandas) Extract +       │                  │ layer            │
│ Air Quality   │               │  Transform               │                  │                  │
│ API           │               └──────────────────────────┘                  └────────┬─────────┘
└───────────────┘                                                                       │ INSERT...SELECT
                                                                                        ▼
                                                       ┌────────────────────────────────────────────┐
                                                       │ Snowflake MARTS layer                       │
                                                       │  Star Schema:                               │
                                                       │   FACT_WEATHER_READINGS                     │
                                                       │   FACT_AIR_QUALITY_READINGS                 │
                                                       │   DIM_CITY (SCD2) · DIM_DATE · DIM_WEATHER  │
                                                       │  Data Vault (parallel):                     │
                                                       │   HUB_CITY · HUB_DATE · LINK · SAT          │
                                                       └────────────────────┬───────────────────────┘
                                                                            │ query results
                                                                            ▼
                                                              ┌──────────────────────────┐
                                                              │ Groq LLaMA 3.1           │
                                                              │ AI Intelligence Report   │
                                                              └──────────────────────────┘
```

![Architecture](docs\architecture.png)

---

## Data Sources

| Source | API | Metrics | Cost |
|---|---|---|---|
| Weather | Open-Meteo Forecast API | temperature, humidity, wind speed, weather code | Free, no key |
| Air Quality | Open-Meteo Air Quality API | PM2.5, UV index, carbon monoxide | Free, no key |

Cities covered: **Mumbai, Bangalore, Delhi, Chennai**.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Ingestion | Python, `requests`, `tenacity` (retry/backoff) |
| Transformation | pandas |
| Warehouse | Snowflake (Standard edition, key-pair auth) |
| Orchestration | Apache Airflow (TaskFlow API) via Docker Compose |
| AI layer | Groq API — `llama-3.1-8b-instant` |
| Modelling | Star schema (Kimball) + Data Vault 2.0 |
| Version control | Git + GitHub |

---

## Data Modelling

### Star Schema (Kimball)

The analytics layer follows Kimball dimensional modelling. Two fact tables share **conformed
dimensions**, which enables drill-across analysis between weather and air quality on the same
city and date.

**Fact tables**
- `FACT_WEATHER_READINGS` — grain: one hourly weather reading per city
- `FACT_AIR_QUALITY_READINGS` — grain: one hourly air quality reading per city

**Dimensions**
- `DIM_CITY` — implements **SCD Type 2** (valid_from / valid_to / is_current) to preserve
  history when city attributes change
- `DIM_DATE` — full calendar dimension (day of week, month, quarter, is_weekend)
- `DIM_WEATHER_CODE` — WMO weather code descriptions and categories

![Star Schema](models/star_schema.png)

The raw data was first normalised to 3NF before being denormalised into the star schema.
The normalisation ERD:

![Normalised ERD](docs/erd_normalised_3nf.png)

### Data Vault 2.0 (parallel model)

A Data Vault model was also built to demonstrate enterprise-grade, audit-friendly modelling.
Hash keys are computed at load time and stamped into every related table, decoupling the
components from one another.

- `HUB_CITY`, `HUB_DATE` — business keys
- `LINK_WEATHER_READING` — relationship between city, date, and the reading grain
- `SAT_CITY_DETAILS`, `SAT_WEATHER_READINGS` — descriptive attributes with load metadata

Every Hub, Link, and Satellite carries `load_date` and `record_source` columns for full
auditability.

![Data Vault Design](models/data_vault_design.png)

Diagrams for both models are in [`/models`](./models).

---

## Orchestration (Apache Airflow)

The pipeline is orchestrated with Apache Airflow running locally via Docker Compose. Two DAGs
run on a daily schedule, each handling a separate data source but writing into the same
conformed star schema.

| DAG | Schedule | Flow |
|---|---|---|
| `weather_pipeline_dag` | Daily 7:00 AM IST | API health sensor → extract → load raw → load fact → AI summary |
| `air_quality_pipeline_dag` | Daily 7:00 AM IST | extract → load raw → load fact |

**Key features**
- Built with the **TaskFlow API** for clean, maintainable DAG code
- **Key-pair authentication** to Snowflake (no passwords; the account enforces MFA)
- **Automatic retries** with exponential backoff
- An **HttpSensor** that waits for the source API to be reachable before extraction
- Credentials stored in Airflow Connections and a mounted `.env` — never hardcoded in DAGs

---

## Project Structure

```
snowflake-weather-pipeline/
├── src/
│   ├── extract.py                 # weather extract from Open-Meteo
│   ├── extract_air_quality.py     # air quality extract
│   ├── transform.py               # pandas cleaning + typing
│   ├── load.py                    # weather load orchestration
│   ├── load_air_quality.py        # air quality load orchestration
│   ├── snowflake_client.py        # key-pair connection + helpers (Docker/local aware)
│   ├── groq_client.py             # Groq API wrapper
│   ├── ai_summary.py              # generate_full_report() — AI intelligence report
│   └── main.py                    # single-command local pipeline run
├── sql/
│   ├── ddl/                       # table creation scripts (run 01 → 03)
│   └── analytics/                 # window functions, CTEs, joins, MERGE, drill-across
├── airflow/
│   ├── dags/
│   │   ├── weather_pipeline_dag.py
│   │   └── air_quality_pipeline_dag.py
│   ├── docker-compose.yaml        # Airflow stack definition
│   └── requirements-airflow.txt   # provider packages for the Airflow image
├── models/                        # star schema + data vault diagrams (PNG)
├── docs/                          # architecture diagram, AI output, design notes
├── config/                        # .env + RSA keys (gitignored)
├── requirements.txt
└── README.md
```

---

## Setup Instructions

### Prerequisites
- Python 3.11+
- A Snowflake account (free trial)
- A Groq API key (free at console.groq.com)
- Docker Desktop (for Airflow)

### 1. Clone and set up the Python environment

```bash
git clone https://github.com/Sheldie1027/snowflake-weather-pipeline.git
cd snowflake-weather-pipeline
python -m venv venv
venv\Scripts\activate            # Windows
pip install -r requirements.txt
```

### 2. Configure credentials

```bash
copy config\.env.example config\.env
```

Fill in your Snowflake account, user, and Groq API key. This project uses **key-pair
authentication** — generate an RSA key pair, register the public key on your Snowflake user,
and place the private key at `config/rsa_key.pem`.

### 3. Create the Snowflake objects

Run the DDL scripts in order in a Snowsight worksheet:
`sql/ddl/01_create_raw_tables.sql` → `02_create_dim_tables.sql` → `03_create_fact_table.sql`

### 4. Run the pipeline locally (without Airflow)

```bash
python src/main.py
```

### 5. Run with Airflow orchestration

1. Ensure Docker Desktop is running
2. From your Airflow project directory, mount this repo's `src/`, `config/`, and `airflow/dags/`
   folders as volumes (see `airflow/docker-compose.yaml`)
3. Start the stack:
   ```bash
   docker compose up airflow-init
   docker compose up -d
   ```
4. Open the Airflow UI at `http://localhost:8080`
5. Add a Snowflake connection (`snowflake_default`) using key-pair auth
6. Add an HTTP connection (`open_meteo_api`)
7. Enable and trigger the DAGs

> **Note:** The volume paths in `docker-compose.yaml` are absolute and reflect the original
> development machine. Update them to match your local clone location.

---

## Sample Analytics

The `sql/analytics/` folder contains queries demonstrating:
- Window functions (`ROW_NUMBER`, `RANK`, `LAG`/`LEAD`, rolling averages)
- CTEs and chained transformations
- Advanced aggregation (`ROLLUP`, `CUBE`, `GROUPING SETS`)
- `MERGE` upserts and soft-delete patterns
- **Drill-across** queries joining weather and air quality via conformed dimensions

Example insight: combining both fact tables surfaces days where high temperature **and**
elevated PM2.5 occurred together — useful for public health alerting.

---

## Engineering Practices

- **Key-pair authentication** end to end — no plaintext passwords anywhere
- **Least-privilege RBAC** — a dedicated `PIPELINE_ROLE` rather than `ACCOUNTADMIN` for loads
- **Idempotent, atomic tasks** in Airflow with retries and sensors
- **Timezone-aware datetimes** throughout (no deprecated `utcnow()`)
- **Resilient extraction** — exponential backoff on API calls, graceful per-city failure handling
- Secrets isolated in `.env` and Airflow Connections; never committed

---

## Roadmap

This is an evolving project built over a multi-week data engineering programme.

- ✅ **Week 1** — Snowflake foundations, Python ETL, star schema, SCD2, Groq AI summary
- ✅ **Week 2** — Apache Airflow orchestration, second data source (air quality), Data Vault 2.0
- ⏭ **Upcoming** — warehouse-native transformations, data quality testing, and documentation

---

## License

This project is for educational and portfolio purposes.
