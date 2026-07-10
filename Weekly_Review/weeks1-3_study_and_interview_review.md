# Weather Intelligence Pipeline — Complete Study & Interview Review (Weeks 1–3)

A single consolidated reference covering everything you built and learned across
Weeks 1, 2 and 3. Use it two ways:

- **Flashcards** — the short Q/A tables. Cover the right column, recall the answer.
- **Interview prep** — the prose sections. These are how you *explain* a concept
  out loud when a hiring manager asks. Read them until you can say them without notes.

At the end there are war stories (real bugs you fixed — the most valuable interview
material you have) and a "walk me through your pipeline" system-design script.

---

## The project in one breath

*"I built an end-to-end ELT pipeline that ingests weather and air quality data for
four Indian cities from the Open-Meteo APIs, loads it raw into Snowflake, transforms
it with dbt into a tested star schema, orchestrates the whole thing with Airflow in
Docker, and generates a natural-language intelligence report with an LLM. Everything
is version-controlled, tested, and documented, and it runs at zero infrastructure cost."*

Memorise that. It's your opening line for any "tell me about a project" question.

---
---

# PART 1 — SNOWFLAKE FOUNDATIONS (Week 1)

## Interview-depth explanation

Snowflake is a **cloud data warehouse** whose defining feature is the **separation of
storage and compute**. In a traditional database, storage and processing are bolted
together — if you need more query power you have to scale the whole machine, data and
all. Snowflake splits them: your data sits in cloud storage (on S3 under the hood),
and **virtual warehouses** (compute clusters) spin up independently to run queries
against it. You can resize compute, or run several warehouses against the same data,
without touching the storage. You pay for storage and compute separately.

This matters because it means **compute is elastic and pausable**. A warehouse can
`AUTO_SUSPEND` after 60 seconds of inactivity and `AUTO_RESUME` the instant a query
arrives — so you're only billed for compute while you're actually running queries.
For a portfolio project that's the difference between a few dollars a month and
draining a trial credit in days.

Under the storage layer, Snowflake stores data in **micro-partitions** — small,
immutable, columnar chunks (~50–500MB uncompressed) that it creates and manages
automatically. Each micro-partition carries metadata (min/max values per column),
which lets Snowflake **prune** — skip partitions that can't contain matching rows —
so queries scan far less data than the full table. You don't manage partitions
manually the way you would in some systems; it's automatic.

Snowflake also gives you **Time Travel** (query or restore data as it was up to N
days ago) and **zero-copy cloning** (instantly clone a table/database without
duplicating storage — it just points at the same micro-partitions until something
changes). Both fall out naturally from the immutable micro-partition design.

## Flashcards

| Question | Answer |
|---|---|
| Snowflake's defining architectural feature? | Separation of storage and compute |
| What is a virtual warehouse? | An independent compute cluster that runs queries; sized/paused separately from storage |
| Why does storage/compute separation matter? | Elastic, pausable compute — pay only while querying; scale compute without moving data |
| What is a micro-partition? | Small, immutable, columnar storage chunk Snowflake manages automatically |
| What is pruning? | Skipping micro-partitions that can't match a query, using min/max metadata |
| AUTO_SUSPEND / AUTO_RESUME? | Warehouse pauses after idle seconds, wakes instantly on the next query |
| Time Travel? | Query/restore data as it existed up to N days ago |
| Zero-copy clone? | Instant clone with no storage duplication until data diverges |

## What you actually configured

- Warehouse `COMPUTE_WH` with `AUTO_SUSPEND=60`, `AUTO_RESUME=TRUE`
- Database `WEATHER_DB` with schemas: `RAW`, `STAGING`, `MARTS`, `DBT_DEV`
- A least-privilege role `PIPELINE_ROLE` (not ACCOUNTADMIN) for the pipeline to use
- Key-pair (RSA) authentication instead of password (because MFA was enforced)

---

# PART 2 — PYTHON ETL & KEY-PAIR AUTH (Week 1)

## Interview-depth explanation

The ingestion layer is plain Python. It calls the Open-Meteo REST APIs with the
`requests` library, shapes the JSON into tabular form with `pandas`, and writes it
into Snowflake's `RAW` schema. The design principle is **land raw, transform later** —
the Python does as little transformation as possible so the raw tables are a faithful
record of what the API returned. That's the "EL" of ELT.

**Authentication is key-pair, not password.** Because the Snowflake account enforced
MFA, a username/password login from a script would prompt for a second factor and
hang. Key-pair auth solves this: you generate an RSA public/private key pair, register
the *public* key on the Snowflake user (`ALTER USER ... SET RSA_PUBLIC_KEY=...`), and
the Python connector signs its connection with the *private* key. No interactive
prompt, no password in the code. On Windows there was no OpenSSL available, so the
key pair was generated using Python's `cryptography` library directly.

**Idempotency** is the other big idea here — and the source of a real bug later.
An idempotent load can run twice and leave the data in the same state as running it
once. The naive version of the pipeline wasn't idempotent: re-running it inserted the
same city+timestamp rows again, creating duplicates in RAW. That got cleaned up
downstream in dbt (dedup in staging), but the lesson is that ingestion should ideally
be safe to re-run.

One code-hygiene note that comes up: use timezone-aware UTC timestamps —
`datetime.now(timezone.utc)` — never the deprecated `datetime.utcnow()`.

## Flashcards

| Question | Answer |
|---|---|
| Why key-pair auth instead of password? | Account enforced MFA; a scripted password login would hang on the 2FA prompt |
| Which key goes on the Snowflake user? | The public key (private key stays with the client and signs the connection) |
| Why generate keys with Python's cryptography lib? | No OpenSSL available on the Windows machine |
| What does "land raw, transform later" mean? | Load API data untouched into RAW; do all transformation afterward (the EL of ELT) |
| What is idempotency? | Running a load twice leaves the same result as running it once (no duplicates) |
| Correct UTC timestamp call? | datetime.now(timezone.utc) — never the deprecated utcnow() |

---

# PART 3 — DIMENSIONAL MODELLING: KIMBALL STAR SCHEMA (Week 1)

## Interview-depth explanation

A **star schema** organises data into two kinds of table: **facts** and
**dimensions**. Facts hold the measurements — the numbers you aggregate (temperature,
humidity, PM2.5). Dimensions hold the descriptive context you slice those numbers by
(which city, which date, which weather condition). Drawn out, one central fact table
surrounded by dimension tables looks like a star — hence the name.

The **grain** of a fact table is the single most important design decision: it's what
one row *means*. Your `fct_weather_readings` grain is "one hourly weather reading per
city." Getting the grain explicit and consistent is what makes aggregations correct;
mixing grains is how you get double-counting.

Dimensions connect to facts through **surrogate keys** — meaningless integer/hash keys
generated by the warehouse, rather than "natural" business keys like a city name. Why?
Natural keys can change (a city gets renamed) or collide; surrogate keys are stable,
compact, and let you track history. In dbt you generated these with
`dbt_utils.generate_surrogate_key`.

**Slowly Changing Dimensions (SCD)** handle the fact that dimension attributes change
over time. SCD Type 1 overwrites the old value (no history). **SCD Type 2** keeps
history by adding a new row each time an attribute changes, with valid-from/valid-to
dates — so you can ask "what did this city's record look like on July 1st." You
implemented SCD2 on the city dimension using a dbt snapshot.

A **drill-across** query combines measures from two different fact tables through their
**conformed dimensions** — dimensions that mean the same thing to both facts. Because
`fct_weather_readings` and `fct_air_quality_readings` share the same `dim_city` and
date grain, you can join them to report temperature and PM2.5 side by side per city.

## Flashcards

| Question | Answer |
|---|---|
| Fact table holds…? | Measurements / numbers you aggregate |
| Dimension table holds…? | Descriptive context you slice facts by |
| What is the grain? | What a single fact row represents (e.g. one hourly reading per city) |
| Why surrogate keys over natural keys? | Stable, compact, collision-free, enable history tracking |
| SCD Type 1 vs Type 2? | Type 1 overwrites (no history); Type 2 adds a new dated row (keeps history) |
| How did you implement SCD2? | A dbt snapshot on the city dimension |
| What is a conformed dimension? | A dimension shared consistently across multiple fact tables |
| What is a drill-across query? | Combining measures from two facts via their conformed dimensions |
| Your fact tables? | fct_weather_readings, fct_air_quality_readings |
| Your dimensions? | dim_city, dim_date, dim_weather_code |

---

# PART 4 — DATA VAULT 2.0 (Week 2)

## Interview-depth explanation

Data Vault 2.0 is a second modelling approach you built alongside the star schema, to
show you understand more than one paradigm. Where a star schema is optimised for
*querying* (analysts love it), Data Vault is optimised for *auditability, history, and
loading flexibility* — it's common in regulated enterprise environments.

It has three building blocks:

- **Hubs** — the unique list of business keys (e.g. a hub of cities). Just the key and
  its metadata, nothing descriptive.
- **Links** — the relationships/transactions between hubs (e.g. a reading linking a
  city and a time).
- **Satellites** — the descriptive, changing attributes hanging off a hub or link
  (e.g. the actual temperature/humidity values, with load timestamps).

The point of splitting it this way is that each piece can be loaded independently and
in parallel, and everything is insert-only with hash keys and load timestamps — so you
get a complete, auditable history of every change without ever updating a row. It's
more tables and more joins than a star schema, which is exactly why you *also* keep the
star schema for actual analytics.

## Flashcards

| Question | Answer |
|---|---|
| What is Data Vault optimised for? | Auditability, history, parallel/flexible loading (enterprise, regulated) |
| Star schema optimised for? | Querying and analytics |
| Hub = ? | Unique business keys + metadata |
| Link = ? | Relationships/transactions between hubs |
| Satellite = ? | Descriptive, changing attributes with load timestamps |
| Why insert-only with hash keys? | Full auditable history; no row is ever updated |
| Why keep both DV and star schema? | DV for audit/history; star for fast analytics |

---

# PART 5 — APACHE AIRFLOW ORCHESTRATION (Week 2)

## Interview-depth explanation

Airflow is the **orchestrator** — it schedules and runs your pipeline, handles
dependencies between steps, retries failures, and gives you visibility into what ran
when. You run it locally via **Docker Compose**, which stands up the Airflow services
(webserver, scheduler, worker, triggerer) plus a metadata database as containers.

The core Airflow concept is the **DAG** — a Directed Acyclic Graph. "Directed" =
steps have a direction (A before B). "Acyclic" = no loops (a pipeline that circled back
on itself would never finish). Each node is a **task**; you wire tasks together to
express "this runs, then this, then this." Your ingestion DAG (`weather_pipeline_dag`)
runs: sensor → extract → load raw → load fact → AI summary.

Tasks are created by **operators** — a `BashOperator` runs a shell command, a
`PythonOperator` runs a Python function, a `TriggerDagRunOperator` fires off another
DAG. **Sensors** are a special operator that waits for a condition before proceeding.
Tasks pass small bits of data to each other through **XCom** (cross-communication).

Two operational features you actually used:

- **Pools** — you created `open_meteo_pool` with 2 slots to throttle concurrent API
  calls, so the pipeline never hammers Open-Meteo with too many simultaneous requests.
- **TriggerDagRunOperator** — your ingestion DAG triggers the separate
  `dbt_transform_dag` when loading finishes, chaining ingestion → transformation into
  one orchestrated flow.

A subtle but important detail: in DAG code, a task's `start_date` should reflect when
the pipeline logically begins, and you set concrete dates using the actual date you
did the work — not a placeholder.

## Flashcards

| Question | Answer |
|---|---|
| What does Airflow do? | Schedules, runs, retries, and monitors pipeline tasks with dependencies |
| DAG stands for? | Directed Acyclic Graph |
| Why acyclic? | No loops — a cyclic pipeline would never complete |
| What is a task vs an operator? | A task is a node; an operator is the template that defines what a task does |
| BashOperator / PythonOperator? | Run a shell command / run a Python function |
| What is a sensor? | An operator that waits for a condition before proceeding |
| What is XCom? | The mechanism tasks use to pass small data between each other |
| What is an Airflow pool? | A concurrency limiter — a fixed number of slots throttling parallel tasks |
| Your pool and why? | open_meteo_pool (2 slots) to throttle API calls |
| How do two DAGs chain? | TriggerDagRunOperator — one DAG triggers another |
| How do you run Airflow locally? | Docker Compose (webserver, scheduler, worker, triggerer, metadata DB) |

---

# PART 6 — dbt & ANALYTICS ENGINEERING (Week 3)

## Interview-depth explanation

dbt (data build tool) is the **transformation** layer — the "T" in ELT. It lets you
write transformations as **SQL SELECT statements** that dbt turns into tables and views
in Snowflake, while adding software-engineering practices on top: version control,
testing, documentation, dependency management, and modularity.

The single most important idea is **`ref()`**. Instead of hardcoding a table name, a
model says `{{ ref('stg_weather') }}`. This does two things: it tells dbt this model
*depends on* stg_weather (so dbt knows the run order automatically), and it makes the
project portable across environments (dev/prod schemas resolve at compile time). The
sibling function `source()` does the same for raw tables loaded by an external process —
and declaring sources also unlocks freshness checks.

Models are organised into **layers**, each with a job:

| Layer | Purpose | Materialization |
|---|---|---|
| Staging (`stg_`) | Clean + dedup, 1:1 with a source | view |
| Intermediate (`int_`) | Reusable business logic, joins | view |
| Marts (`dim_`,`fct_`,`mart_`) | Final tables consumers read | table / incremental |

**Materialization** is how dbt builds a model in the warehouse:

- **view** — a saved query; always fresh, stores no data, cheap. Good for staging.
- **table** — physically built; fast to query, rebuilt each run. Good for small marts.
- **incremental** — only processes *new* rows each run instead of rebuilding. Essential
  for large fact tables. With `strategy='merge'` and a `unique_key`, dbt upserts —
  inserting new rows and updating matching ones — which makes re-runs **idempotent**
  (no duplicates).
- **ephemeral** — inlined as a CTE into downstream models, never built as its own object.

**Snapshots** implement SCD Type 2 automatically. With `strategy='check'` and
`check_cols`, each run compares the watched columns to last time; if they changed, it
closes the old row (valid_to) and opens a new one (valid_from) — a full timeline of how
each record looked over time. This is *not* a backup; it's living, queryable history.

**Macros and Jinja**: dbt SQL is templated with Jinja, so you can use variables, loops,
and reusable functions. You wrote a `celsius_to_fahrenheit` macro and used
`dbt_utils.generate_surrogate_key` to build stable keys. **Seeds** are small CSV files
(your `weather_codes.csv`) that dbt loads as tables. **Packages** (`dbt_utils`,
`dbt_expectations`) are installed via `packages.yml` + `dbt deps`.

Finally, dbt **auto-generates documentation and a lineage graph** — a visual DAG of
every model from raw source to final output. **Exposures** extend that graph to
downstream consumers (your AI report), so the lineage runs source → marts → AI in one
picture.

## Flashcards

| Question | Answer |
|---|---|
| What is dbt? | The transformation layer (the T in ELT) — SQL SELECTs turned into tested, documented models |
| What does ref() do? | References another model, building the dependency graph and portability |
| What does source() do? | References externally-loaded raw tables; enables freshness checks |
| The three model layers? | Staging (view), Intermediate (view), Marts (table/incremental) |
| view materialization? | Saved query; always fresh, stores no data, cheap |
| table materialization? | Physically built, rebuilt each run; fast to query |
| incremental materialization? | Processes only new rows; merge + unique_key makes it idempotent |
| ephemeral materialization? | Inlined as a CTE into downstream models; never built as an object |
| What does a snapshot do? | Automatic SCD Type 2 — tracks column changes with valid-from/to dates |
| Snapshot vs backup? | Backup = static restore copy; snapshot = living queryable history |
| What is a seed? | A small CSV dbt loads as a table (e.g. weather_codes.csv) |
| What is a macro? | A reusable Jinja-templated SQL function |
| How do you install packages? | packages.yml + dbt deps |
| What is an exposure? | Documentation of a downstream data consumer (your AI report) in lineage |
| dbt run vs dbt build? | run = models only; build = models + tests + seeds + snapshots in order |

---

# PART 7 — DATA QUALITY & TESTING (Week 3)

## Interview-depth explanation

The thing that turns this from "some SQL" into a **production pipeline** is that every
run is validated. If the API ever returns garbage — a temperature of 200°C, a negative
particulate reading, a duplicated grain — dbt tests **fail the pipeline before that data
reaches the marts or the AI**. That "fail fast on bad data" property is what interviewers
mean by data quality.

There are four kinds of test in your project:

1. **Built-in generic tests** — declared in YAML on a column: `unique`, `not_null`,
   `accepted_values` (value in an allowed set), `relationships` (foreign-key integrity
   between models).
2. **Singular tests** — a custom `.sql` file that returns rows that *violate* a rule; if
   it returns any rows, the test fails. You wrote one asserting temperature stays within
   a physical range.
3. **dbt_expectations** — a package (inspired by Great Expectations) with richer
   assertions: `expect_column_values_to_be_between` (ranges: temperature −50 to 60,
   humidity 0 to 100, PM2.5 0 to 1000) and `expect_table_row_count_to_be_between`
   (catches an empty table = broken pipeline, or an absurdly large one = duplication bug).
4. **dbt_utils** — `unique_combination_of_columns` to assert **grain**: no city+date
   appears twice in the daily summary mart.

Separately, **source freshness** (`dbt source freshness`) checks the newest `loaded_at`
timestamp in each raw source against now, and warns at 24h / errors at 48h — a direct
signal that the ingestion pipeline has stalled.

Tests also have **severity**: `warn` (logs a warning, keeps going) vs `error` (fails the
run). You use both deliberately.

## Flashcards

| Question | Answer |
|---|---|
| Point of testing in one line? | Fail the pipeline on bad data before it reaches marts or the AI |
| Four built-in generic tests? | unique, not_null, accepted_values, relationships |
| What is a singular test? | A custom SQL file returning rule-violating rows; any rows = fail |
| What does dbt_expectations add? | Rich assertions — value ranges, row counts, types |
| Example range tests you set? | Temperature −50/60, humidity 0/100, PM2.5 0/1000 |
| How do you assert grain? | dbt_utils.unique_combination_of_columns (city_name + reading_date) |
| What does source freshness check? | Newest loaded_at vs now; warns/errors if data is stale |
| Test severity levels? | warn (logs, continues) vs error (fails the run) |

---

# PART 8 — AI / LLM INTEGRATION (Groq)

## Interview-depth explanation

The final layer generates a natural-language **weather intelligence report** using an
LLM — Groq's `llama-3.1-8b-instant`. Crucially, the AI does **not** read raw data. It
reads `mart_city_daily_summary` — a tested, documented dbt mart — so the model only ever
sees validated, pre-aggregated input. This is the whole payoff of the pipeline: clean
data in means a coherent, trustworthy summary out, and dbt tests guarantee the "clean"
part every run.

The Python (`ai_summary.py`) has two functions worth naming: `fetch_rich_summary()`
pulls the mart data and formats it into a compact text block; `generate_full_report()`
sends that to the LLM and returns the report. Keeping fetch and generate separate means
you can change *where the data comes from* (you repointed it from ad-hoc SQL to the dbt
mart) without touching the generation logic.

**The Claude cost point** (worth being able to explain): Claude Pro is a flat-fee *chat*
subscription; the Claude *API* is separate, per-token billing. They don't share credit.
For a cost-free LLM comparison you keep Groq in production and compare against Claude
manually via the chat product — no API spend.

## Flashcards

| Question | Answer |
|---|---|
| Which model generates the report? | Groq llama-3.1-8b-instant |
| What does the AI read from? | mart_city_daily_summary (a tested dbt mart), not raw data |
| Why feed the AI a mart, not raw? | Validated, pre-aggregated input → coherent output; tests guard quality |
| Two key functions in ai_summary.py? | fetch_rich_summary() (get + format data), generate_full_report() (call LLM) |
| Why split fetch from generate? | Change the data source without touching generation logic |
| Claude Pro vs Claude API? | Pro = flat-fee chat; API = per-token, separate billing; no shared credit |

---

# PART 9 — ADVANCED SQL TECHNIQUES

## Interview-depth explanation

Across the project you used SQL well beyond basic SELECTs:

- **Window functions** — `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)` for
  deduplication (keep the latest row per city+timestamp), and rolling averages over time
  windows. Window functions compute across a set of rows *related to the current row*
  without collapsing them into a GROUP BY.
- **CTEs** (`WITH ... AS`) — you structure every dbt model as named CTEs
  (`with weather as (...), air_quality as (...), final as (...)`) for readability.
- **MERGE** — the upsert statement behind incremental models: match on a key, update
  when matched, insert when not. You inspected the compiled MERGE dbt generates.
- **CORR()** — correlation between two measures (e.g. temperature vs humidity).
- **Date spine / gap detection** — generating a complete series of dates and
  left-joining to find missing readings.
- **QUALIFY** — Snowflake's clause for filtering on a window function result directly
  (e.g. `QUALIFY row_number() ... = 1`) without a subquery.

One hard rule you learned: **never use `rows` as a column alias** — it's a reserved word
and errors. Use `cnt` or `rws`.

## Flashcards

| Question | Answer |
|---|---|
| How did you dedup rows? | ROW_NUMBER() OVER (PARTITION BY city, timestamp ORDER BY loaded_at DESC), keep rn=1 |
| What is a window function? | Computes across related rows without collapsing them into a GROUP BY |
| What is a CTE? | A named subquery (WITH ... AS) improving readability/modularity |
| What does MERGE do? | Upsert: update on key match, insert when no match (drives incremental models) |
| CORR()? | Correlation between two numeric columns |
| What is a date spine? | A generated complete date series, join to find gaps/missing rows |
| What does QUALIFY do? | Filters on a window function result without a subquery (Snowflake) |
| Forbidden column alias? | `rows` — reserved word; use cnt or rws |

---
---

# PART 10 — WAR STORIES (your best interview material)

Interviewers love "tell me about a bug you fixed." These are real, specific, and show
judgement. Each is framed as **Situation → Problem → Fix → Lesson.**

### 1. Duplicate rows from a non-idempotent pipeline
- **Situation:** The `unique` test on `reading_sk` failed with 1,440 duplicates.
- **Problem:** Repeated pipeline runs had inserted the same city+timestamp rows into RAW.
  The staging model faithfully carried the dupes through, and stale data already sat in
  the incremental fact table.
- **Fix:** Added a `ROW_NUMBER()` dedup in staging (partition by city + timestamp, keep
  the latest by `loaded_at`), then ran `--full-refresh` on the fact table to clear the
  stale incremental data.
- **Lesson:** Incremental models don't retroactively fix historic dupes — you need a full
  refresh. And ingestion should be idempotent in the first place.

### 2. "Ambiguous column name" in a surrogate-key macro
- **Situation:** `generate_surrogate_key(['city_name', ...])` errored in a fact model.
- **Problem:** The fact joined two CTEs that both had a `city_name` column, so `city_name`
  alone was ambiguous.
- **Fix:** Qualified the column with its CTE alias — `'w.city_name'`, `'aq.city_name'`.
- **Lesson:** Macros generate SQL literally; unqualified columns break under joins.

### 3. dbt broke every Airflow container (dependency hell)
- **Situation:** Adding `dbt-core`/`dbt-snowflake` to Airflow's
  `_PIP_ADDITIONAL_REQUIREMENTS` sent pip into endless dependency backtracking
  (opentelemetry conflicts); all containers went unhealthy for 9+ minutes.
- **Problem:** dbt's dependencies conflicted with Airflow's own pinned packages.
- **Fix:** Reverted Airflow's requirements, then installed dbt in an **isolated
  virtualenv** inside the worker — later baked permanently into a **custom Dockerfile**.
- **Lesson:** Isolate conflicting tools instead of forcing them into one environment.
  This is *the* strongest story you have — it shows real debugging under pressure and a
  clean architectural resolution.

### 4. Windows path broke dbt in the Linux container
- **Situation:** `profiles.yml` had a Windows private-key path that failed inside Docker.
- **Problem:** Backslashes in the path also triggered a Python `\U` escape error
  (`truncated \UXXXXXXXX escape`).
- **Fix:** Used `env_var()` with a **forward-slash** fallback path, and the DAG passes the
  Linux container path explicitly.
- **Lesson:** Paths differ across host and container; forward slashes and env vars keep
  configs portable.

### 5. dbt models landing in the wrong schema
- **Situation:** Views were appearing in `MARTS` instead of the intended `DBT_DEV`.
- **Fix:** Corrected the schema in `profiles.yml` and dropped the misplaced view.
- **Lesson:** dbt's target schema is set in the profile; a wrong line silently misroutes
  everything.

### 6. The trial-account expiry cliff (ops judgement, not code)
- **Situation:** The original Snowflake trial was days from expiring mid-bootcamp.
- **Fix:** Migrated to a separate account with ~100 days of credit — reused the existing
  RSA key, re-registered the public key, ran a consolidated rebuild script, and updated
  `.env` / `profiles.yml` / the Airflow connection.
- **Lesson:** Having a repeatable rebuild script (`00_full_rebuild.sql`) made a full
  environment migration a routine task, not a crisis.

---

# PART 11 — RAPID-FIRE FLASHCARDS (mixed, all weeks)

Cover the right column. If you can't answer in one sentence, revisit that part.

| Question | Answer |
|---|---|
| ETL vs ELT? | ETL transforms before load; ELT loads raw then transforms in-warehouse |
| Why is ELT better here? | Preserves raw source of truth; transforms are versioned SQL; warehouse does the compute |
| Storage/compute separation buys you what? | Elastic, pausable, independently-scalable compute |
| What role runs your pipeline and why? | PIPELINE_ROLE — least privilege, not ACCOUNTADMIN |
| Grain of your weather fact? | One hourly reading per city |
| How do you track dimension history? | dbt snapshot = SCD Type 2 |
| How do you avoid duplicate fact rows on re-run? | Incremental + merge + unique_key (idempotent) |
| What makes ingestion safe to re-run? | Idempotency |
| How does dbt know model run order? | The ref()-built dependency graph |
| How do you catch a stalled pipeline? | Source freshness (warn 24h / error 48h) |
| How does the AI avoid seeing bad data? | It reads a tested mart; dbt tests gate every run |
| How are the two facts combined? | Drill-across on conformed dim_city + date |
| What throttles your API calls? | Airflow pool (open_meteo_pool, 2 slots) |
| How is dbt run from Airflow? | Isolated venv baked into a custom Airflow image; DAG BashOperator |
| What chains ingestion to transformation? | TriggerDagRunOperator |
| Cost control on Snowflake? | AUTO_SUSPEND=60, AUTO_RESUME=TRUE |

---

# PART 12 — PROJECT-NARRATIVE / BEHAVIOURAL ANSWERS

**"Tell me about this project."**
Use the one-breath summary at the top, then offer to go deeper on any layer.

**"What was the hardest part?"**
The dbt-in-Airflow dependency conflict (War Story 3). Walk through situation → the
backtracking failure → isolating dbt in a venv → baking it into a custom image. It shows
you can debug infra under pressure and land a clean, reproducible fix.

**"How do you ensure data quality?"**
Layered dbt tests — built-in, singular, dbt_expectations ranges, dbt_utils grain checks —
plus source freshness. The pipeline fails before bad data reaches the marts or the AI.
Give the concrete example: a 200°C temperature would trip the range test and stop the run.

**"Why did you use two data models (star + Data Vault)?"**
Star schema for fast analytics; Data Vault to show I understand auditable, history-first
enterprise modelling. Different tools for different priorities.

**"What would you do differently / next?"**
Make ingestion idempotent from the start (I fixed dupes downstream instead). Add CI to run
dbt tests on every commit. Compare LLM providers on the same data with a provider switch.

**"What did you learn?"**
That the engineering rigour around the SQL — testing, orchestration, dependency isolation,
documentation, lineage — is what separates a script from a pipeline.

---

# PART 13 — "WALK ME THROUGH YOUR PIPELINE" (system-design script)

Say this top to bottom, pointing at the architecture diagram:

1. **Ingestion.** Airflow triggers Python tasks that call the Open-Meteo Weather and Air
   Quality APIs for four cities. An Airflow pool caps concurrent calls. Data lands raw in
   Snowflake's RAW schema, each row stamped with loaded_at. Auth is Snowflake key-pair.
2. **Trigger.** When loading finishes, the ingestion DAG fires the dbt DAG via
   TriggerDagRunOperator.
3. **Transformation.** dbt (isolated venv in a custom Airflow image) runs staging →
   intermediate → marts. Staging dedups and cleans; marts build the star schema with
   incremental merge facts and an SCD2 city snapshot.
4. **Testing.** dbt tests run every build — uniqueness, not-null, ranges, grain, freshness.
   Bad data fails the run here, before it can propagate.
5. **Serving.** The clean mart_city_daily_summary feeds a Groq LLaMA model, which writes a
   natural-language intelligence report.
6. **Observability.** dbt auto-generates docs and a lineage graph running from raw source
   all the way to the AI report (declared as an exposure).

Then the closing line: *"Everything is version-controlled, tested, documented, orchestrated,
and runs at zero infrastructure cost."*

---

*End of review. If you can talk through Parts 10, 12 and 13 without notes, you're ready for
the project portion of any data engineering interview.*
