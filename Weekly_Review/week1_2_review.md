# Weeks 1 & 2 — Complete Review

A descriptive walkthrough of every concept covered in the data engineering bootcamp so far.
Use this as your interview prep cheat sheet.

---

## PART 1 — SNOWFLAKE FOUNDATIONS

### Architecture: separation of storage and compute

Snowflake's defining feature is that **storage and compute are independent**. Your data sits
in cloud storage; **virtual warehouses** (compute clusters) spin up to run queries against it.

Why it matters:
- Scale compute up for a heavy job, down for a light one — without moving data
- Pay for storage and compute separately
- Multiple warehouses can query the same data simultaneously without contention

### Virtual warehouses

A **warehouse** is compute, not storage. Sizes go XS, S, M, L... each step doubles compute and
credit burn. For a small learning dataset, XS is correct — going bigger wastes credits.

Cost control:
```sql
ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
```
`AUTO_SUSPEND = 60` sleeps the warehouse after 60 seconds idle. `AUTO_RESUME` wakes it on the
next query. This can double your effective trial credit life.

### Layered schema design (RAW → STAGING → MARTS)

| Layer | Purpose |
|---|---|
| RAW | Landing zone — data exactly as it arrived from the source |
| STAGING | Cleaned and typed, light transformations |
| MARTS | Analytics-ready star schema |

This separation of concerns means raw data is always preserved (you can reprocess), and each
layer has one job.

### Other Snowflake features covered

- **Time Travel** — query data as it existed in the past (`AT (OFFSET => -300)`), restore
  dropped tables with `UNDROP`. Standard edition gives 1 day of history.
- **Zero-Copy Cloning** — `CREATE TABLE x CLONE y` makes an instant copy with no storage cost
  until changes diverge. Great for dev/test environments.
- **Streams** — change data capture. A stream tracks INSERT/UPDATE/DELETE on a table since last
  consumed. Foundation of incremental processing.
- **Tasks** — native scheduling inside Snowflake. Chain with `AFTER`, run on a `SCHEDULE`,
  gate with `WHEN SYSTEM$STREAM_HAS_DATA(...)`.
- **RBAC** — least-privilege roles. A dedicated `PIPELINE_ROLE` with only the grants it needs,
  never `ACCOUNTADMIN` for routine loads.

---

## PART 2 — PYTHON ETL

### The pipeline flow

```
extract.py  -> transform.py -> load.py -> ai_summary.py
   (API)        (pandas)       (Snowflake)   (Groq LLM)
```

### Key components

- **`requests`** — calls the Open-Meteo API, returns JSON
- **`pandas`** — cleans, types, and shapes the data into DataFrames
- **`write_pandas()`** — loads a DataFrame straight into a Snowflake table
- **`snowflake_client.py`** — reusable connection logic, made Docker/local aware
- **`tenacity`** — adds retry-with-backoff to flaky API calls

### Key-pair authentication

Because the Snowflake account enforces MFA, password auth is blocked for programmatic access.
The fix is **key-pair auth**: generate an RSA key pair, register the public key on the user
(`ALTER USER ... SET RSA_PUBLIC_KEY=...`), and have Python sign in with the private key. More
secure than passwords and works headlessly.

### Hard-won debugging lessons

- **Timestamps:** convert to a clean string format before loading, or Snowflake produces
  "Invalid date". Use `pd.to_datetime(..., format="%Y-%m-%dT%H:%M")` then
  `.dt.strftime("%Y-%m-%d %H:%M:%S")`.
- **`write_pandas` timezone warning:** add `use_logical_type=True`.
- **Deprecated datetime:** always `datetime.now(timezone.utc)`, never `utcnow()`.
- **Windows commands:** PowerShell, not Linux — `New-Item` not `touch`,
  `Remove-Item -Recurse -Force` not `rm -rf`, `dir` not `ls`.

---

## PART 3 — DIMENSIONAL MODELLING (KIMBALL)

### Star schema

A central **fact table** surrounded by **dimension tables**. Optimised for analytical queries —
few joins, columnar-friendly.

- **Fact table** = measurements + foreign keys. `FACT_WEATHER_READINGS` holds temperature,
  humidity, wind, plus keys to each dimension.
- **Dimension tables** = descriptive context. `DIM_CITY`, `DIM_DATE`, `DIM_WEATHER_CODE`.

### Grain — the most important decision

The **grain** is a one-sentence statement of what a single fact row represents. Write it before
any SQL.

> Grain: one hourly weather reading for one city.

Get this wrong and the whole model is confused. Both your fact tables share the same grain
(city + hour), which is what lets them join.

### Surrogate keys

A **surrogate key** is a stable, system-generated integer (e.g. `city_sk`), separate from the
**natural key** (e.g. `city_nk` = "Mumbai"). Natural keys can change, duplicate, or have messy
formatting; surrogate keys insulate the model from source changes.

### SCD Type 2 (Slowly Changing Dimensions)

Preserves history when a dimension attribute changes. Instead of overwriting:

1. Expire the old row: `is_current = FALSE`, `valid_to = CURRENT_TIMESTAMP()`
2. Insert a new row with the new values, `is_current = TRUE`

Old facts still point to the old dimension row; new facts point to the new one. Full audit trail.

| Type | Behaviour | Use |
|---|---|---|
| Type 1 | Overwrite, no history | Fixing typos |
| Type 2 | New row + expire old | History matters (your DIM_CITY) |
| Type 3 | Add a "previous" column | One level of history, rarely used |

### Normalisation to 3NF

Before the star schema you normalised to 3rd Normal Form — removing redundancy and transitive
dependencies (e.g. weather code description split into its own `weather_codes` table). Then you
deliberately denormalised into the star schema for query performance. Knowing both directions
is the point.

### Conformed dimensions & junk dimensions

- **Conformed dimension** — a dimension that means the same thing across multiple facts.
  `DIM_CITY` and `DIM_DATE` are shared by both weather and air quality facts, enabling
  **drill-across** queries.
- **Junk dimension** — groups low-cardinality flags (is_daytime, is_extreme_heat...) into one
  small dimension instead of bloating the fact table.

---

## PART 4 — DATA VAULT 2.0

An enterprise modelling pattern built for auditability and flexibility. Three components:

| Component | Stores | Example |
|---|---|---|
| **Hub** | Unique business keys + load metadata | `HUB_CITY` (city name) |
| **Link** | Relationships between hubs + the grain | `LINK_WEATHER_READING` |
| **Satellite** | Descriptive attributes + load metadata | `SAT_WEATHER_READINGS` |

Every table also carries `load_date` and `record_source` — the two mandatory metadata columns
that make Data Vault fully auditable.

### The hash key — the concept that matters most

This is the part that trips everyone up. The hash key (e.g. `reading_hk`) is:

1. **Computed at LOAD time** from the business keys, e.g.
   `MD5(city_name + '|' + recorded_at)`
2. **Stored** into every related table (Hub, Link, Satellite)
3. **Never recomputed at query time** — you just match on the stored value

So a Satellite doesn't need to store the city name to join — it stores `reading_hk`, which was
stamped onto it at load time. Think of it like a receipt number printed on both copies: you
match on the number, you don't re-derive it from the items.

```sql
-- The join only ever uses the stored hash:
SELECT ...
FROM LINK_WEATHER_READING l
JOIN SAT_WEATHER_READINGS s ON l.reading_hk = s.reading_hk;
```

### Kimball vs Inmon vs Data Vault

| Approach | Style | Best for |
|---|---|---|
| Kimball | Bottom-up dimensional | Fast analytics, BI, known use cases |
| Inmon | Top-down normalised EDW | Single source of truth, large enterprise |
| Data Vault | Hub-Link-Satellite | Auditability, many sources, changing schemas |

Most real systems are hybrid: `RAW → Data Vault → Kimball marts`.

---

## PART 5 — ORCHESTRATION (APACHE AIRFLOW)

### The four components

| Component | Job |
|---|---|
| **Scheduler** | Decides *when* tasks run — reads DAGs, checks schedules/dependencies |
| **Executor** | Actually *runs* the tasks |
| **Webserver** | The UI at localhost:8080 — monitoring and manual triggers |
| **Metadata DB** | Stores DAG definitions, task states, connections, variables |

### Core concepts

- **DAG** — Directed Acyclic Graph. A Python file defining tasks and their order. "Acyclic" =
  no dependency loops, so there's always a clear start and end.
- **Task** — one unit of work. **Operator** — the type of task (PythonOperator,
  SnowflakeOperator, HttpSensor...).
- **TaskFlow API** — the modern `@task` decorator style. Cleaner than classic operators and
  handles XCom automatically when you return values.
- **XCom** — passes small, JSON-serializable data between tasks. Not for DataFrames (convert to
  dict/records and stringify timestamps first).
- **Connections** — stored credentials for external systems (`snowflake_default`).
- **Variables** — key-value config stored in Airflow, not in code.
- **Sensors** — tasks that wait for a condition. `poke` mode holds a worker (short waits);
  `reschedule` mode frees it (long waits).
- **Pools** — limit concurrent tasks against a shared resource (`open_meteo_pool`, 2 slots).

### Scheduling & reliability

- **Cron** — `30 1 * * *` = 1:30am UTC daily (7am IST). Use crontab.guru.
- **Retries** — `retries`, `retry_delay`, `retry_exponential_backoff`.
- **catchup=False** — don't backfill all the missed runs between start_date and now.

### Best practices

- **Idempotent** tasks — running twice = same result as once
- **Atomic** tasks — each does one thing, so retries are cheap
- **No top-level code** — it runs every ~30s when the scheduler parses the file
- **Use Connections/Variables** — never hardcode secrets

### Hard-won Airflow lessons

- `run_id` is a **reserved** keyword — rename your param to `pipeline_run_id`.
- Chain TaskFlow return values with `chain()` from `airflow.models.baseoperator`, not `>>`.
- Wiring code must sit at the **DAG function level**, not inside a task.
- XCom can't serialize pandas Timestamps — `.astype(str)` before returning,
  `pd.to_datetime()` on receipt.
- Always run `docker compose` from the **airflow-project** folder, never elsewhere — wrong
  folder spins up a fresh empty stack and you "lose" your connections.
- The class is `HttpSensor` (singular), not `HttpSensors`.

---

## PART 6 — SQL TECHNIQUES

### Window functions

Operate across a set of rows **without collapsing them** (unlike GROUP BY).

- `ROW_NUMBER()` — unique sequential number
- `RANK()` — same number for ties, skips the next (1,1,3)
- `DENSE_RANK()` — same number for ties, no skip (1,1,2)
- `LAG()/LEAD()` — value from a previous/next row (day-over-day change)
- `PARTITION BY` — divides rows into groups the function works within
- Rolling windows — `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` for a 7-day average

### CTEs and joins

- **CTE** (`WITH x AS (...)`) — a named temporary result set for one query; improves readability
- **INNER JOIN** — only matching rows
- **LEFT JOIN** — all left rows + matches (NULLs where none)
- **Self join** — a table joined to itself to compare its own rows

### Advanced aggregation

- **ROLLUP(a, b)** — hierarchical subtotals: per b, per a, grand total
- **CUBE(a, b)** — every combination of a and b
- **GROUPING SETS** — you pick exactly which groupings you want
- **GROUPING()** — distinguishes real NULLs from subtotal rows

### MERGE (upsert)

Combines INSERT + UPDATE atomically:
```sql
MERGE INTO target USING (source...) ON key
WHEN MATCHED THEN UPDATE ...
WHEN NOT MATCHED THEN INSERT ...
```
Snowflake notes:
- Inline the source in `USING (...)` — **no CTE before MERGE**
- Snowflake has **no `WHEN NOT MATCHED BY SOURCE`** — do soft deletes as a separate UPDATE

### Analytical patterns

- **Drill-across** — join two facts via conformed dimensions
- **Date spine** — `GENERATOR(ROWCOUNT => n)` to produce every expected date and find gaps
- **CORR(a, b)** — statistical correlation, -1 to 1

---

## PART 7 — AI INTEGRATION (GROQ)

- The LLM (`llama-3.1-8b-instant`) takes queried Snowflake stats and writes a natural-language
  intelligence report via `generate_full_report()`.
- **System prompt** sets the role/behaviour; **user message** is the input.
- **temperature** controls randomness (0 = deterministic, 1 = creative); use ~0.3 for summaries.
- **max_tokens** caps response length.
- Prompt engineering matters — structured vs conversational system prompts produce very
  different outputs.

---

## QUICK INTERVIEW ANSWERS

**"Walk me through your pipeline."**
Open-Meteo APIs → Python (requests + pandas) extract and transform → Snowflake RAW layer →
star schema in MARTS (fact + conformed dimensions, SCD2) → Groq LLM summary. Orchestrated by
two Airflow DAGs on a daily schedule, key-pair auth, retries, sensors, least-privilege role.

**"Why a star schema?"**
Analytical workload — aggregations by city/date/condition. Star schemas minimise joins and suit
columnar engines like Snowflake.

**"Kimball or Data Vault?"**
Both. Star schema for analytics performance, Data Vault demonstrated for auditability. Hybrid:
RAW → Vault → marts.

**"How do you handle history?"**
SCD Type 2 on DIM_CITY — expire old row, insert new, with valid_from/valid_to/is_current.

**"Airflow or Snowflake Tasks?"**
Airflow for multi-system pipelines (API + Python + Snowflake). Snowflake Tasks for pure
in-warehouse SQL transforms. I use Airflow for ingestion; Tasks + Streams demonstrated for
warehouse-native incremental loads.
