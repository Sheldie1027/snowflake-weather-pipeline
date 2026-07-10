# Weeks 1–3 — Flashcard Self-Test (Questions Only)

Answer each out loud or on paper in one sentence, then check the **Answer Key** at
the bottom. If you can't answer in a sentence, go back to the matching part in the
full review doc. Grouped by topic; numbered continuously so you can track a score.

---

## Snowflake Foundations

1. What is Snowflake's defining architectural feature?
2. What is a virtual warehouse?
3. Why does storage/compute separation matter?
4. What is a micro-partition?
5. What is pruning?
6. What do AUTO_SUSPEND / AUTO_RESUME do?
7. What is Time Travel?
8. What is a zero-copy clone?

## Python ETL & Key-Pair Auth

9. Why key-pair auth instead of password?
10. Which key goes on the Snowflake user?
11. Why generate the keys with Python's cryptography library?
12. What does "land raw, transform later" mean?
13. What is idempotency?
14. What is the correct UTC timestamp call in Python?

## Dimensional Modelling (Star Schema)

15. What does a fact table hold?
16. What does a dimension table hold?
17. What is the grain of a fact table?
18. Why use surrogate keys over natural keys?
19. SCD Type 1 vs Type 2?
20. How did you implement SCD2?
21. What is a conformed dimension?
22. What is a drill-across query?
23. Name your two fact tables.
24. Name your three dimensions.

## Data Vault 2.0

25. What is Data Vault optimised for?
26. What is a star schema optimised for?
27. What is a Hub?
28. What is a Link?
29. What is a Satellite?
30. Why is Data Vault insert-only with hash keys?
31. Why keep both a Data Vault and a star schema?

## Apache Airflow

32. What does Airflow do?
33. What does DAG stand for?
34. Why must it be acyclic?
35. What is a task vs an operator?
36. What do BashOperator and PythonOperator do?
37. What is a sensor?
38. What is XCom?
39. What is an Airflow pool?
40. What is your pool and why does it exist?
41. How do two DAGs chain together?
42. How do you run Airflow locally?

## dbt & Analytics Engineering

43. What is dbt, in one line?
44. What does ref() do?
45. What does source() do?
46. What are the three model layers and their materializations?
47. What is a view materialization?
48. What is a table materialization?
49. What is an incremental materialization, and what makes it idempotent?
50. What is an ephemeral materialization?
51. What does a dbt snapshot do?
52. Snapshot vs backup — what's the difference?
53. What is a seed?
54. What is a macro?
55. How do you install dbt packages?
56. What is an exposure?
57. dbt run vs dbt build?

## Data Quality & Testing

58. What is the point of testing, in one line?
59. Name the four built-in generic tests.
60. What is a singular test?
61. What does dbt_expectations add?
62. Give an example of a range test you set.
63. How do you assert grain?
64. What does source freshness check?
65. What are the two test severity levels?

## AI / LLM Integration

66. Which model generates the report?
67. What does the AI read from?
68. Why feed the AI a mart instead of raw data?
69. Name the two key functions in ai_summary.py.
70. Why split fetch from generate?
71. Claude Pro vs Claude API?

## Advanced SQL

72. How did you deduplicate rows?
73. What is a window function?
74. What is a CTE?
75. What does MERGE do?
76. What does CORR() do?
77. What is a date spine?
78. What does QUALIFY do?
79. What column alias is forbidden, and why?

## Rapid-Fire (mixed)

80. ETL vs ELT?
81. Why is ELT the better fit here?
82. What role runs your pipeline and why?
83. What throttles your API calls?
84. How is dbt actually run from Airflow?
85. What chains ingestion to transformation?
86. What are your two Snowflake cost controls?

---
---

# ANSWER KEY

*Don't scroll here until you've answered. Grade yourself out of 86.*

1. Separation of storage and compute.
2. An independent compute cluster that runs queries, sized/paused separately from storage.
3. Elastic, pausable compute — pay only while querying; scale compute without moving data.
4. A small, immutable, columnar storage chunk Snowflake manages automatically.
5. Skipping micro-partitions that can't match a query, using min/max metadata.
6. Warehouse pauses after idle seconds, wakes instantly on the next query.
7. Query or restore data as it existed up to N days ago.
8. An instant clone with no storage duplication until the data diverges.
9. The account enforced MFA; a scripted password login would hang on the 2FA prompt.
10. The public key (the private key stays with the client and signs the connection).
11. No OpenSSL was available on the Windows machine.
12. Load API data untouched into RAW; do all transformation afterward (the EL of ELT).
13. Running a load twice leaves the same result as running it once — no duplicates.
14. datetime.now(timezone.utc) — never the deprecated utcnow().
15. The measurements / numbers you aggregate.
16. The descriptive context you slice facts by.
17. What a single fact row represents (e.g. one hourly reading per city).
18. Stable, compact, collision-free, and they enable history tracking.
19. Type 1 overwrites the old value (no history); Type 2 adds a new dated row (keeps history).
20. A dbt snapshot on the city dimension.
21. A dimension shared consistently across multiple fact tables.
22. Combining measures from two fact tables via their conformed dimensions.
23. fct_weather_readings and fct_air_quality_readings.
24. dim_city, dim_date, dim_weather_code.
25. Auditability, history, and parallel/flexible loading (enterprise, regulated settings).
26. Querying and analytics.
27. The unique list of business keys plus metadata.
28. The relationships/transactions between hubs.
29. The descriptive, changing attributes with load timestamps.
30. To keep a complete, auditable history — no row is ever updated.
31. Data Vault for audit/history; star schema for fast analytics.
32. Schedules, runs, retries, and monitors pipeline tasks with dependencies.
33. Directed Acyclic Graph.
34. No loops — a cyclic pipeline would never complete.
35. A task is a node; an operator is the template defining what a task does.
36. Run a shell command / run a Python function.
37. An operator that waits for a condition before proceeding.
38. The mechanism tasks use to pass small data between each other.
39. A concurrency limiter — a fixed number of slots throttling parallel tasks.
40. open_meteo_pool (2 slots), to throttle concurrent API calls.
41. TriggerDagRunOperator — one DAG triggers another.
42. Docker Compose (webserver, scheduler, worker, triggerer, metadata DB).
43. The transformation layer (the T in ELT) — SQL SELECTs turned into tested, documented models.
44. References another model, building the dependency graph and keeping the project portable.
45. References externally-loaded raw tables; also enables freshness checks.
46. Staging (view), Intermediate (view), Marts (table/incremental).
47. A saved query; always fresh, stores no data, cheap.
48. Physically built and rebuilt each run; fast to query.
49. Processes only new rows; merge + unique_key upserts, making re-runs idempotent.
50. Inlined as a CTE into downstream models; never built as its own object.
51. Automatic SCD Type 2 — tracks column changes with valid-from/to dates.
52. A backup is a static restore copy; a snapshot is living, queryable history.
53. A small CSV dbt loads as a table (e.g. weather_codes.csv).
54. A reusable Jinja-templated SQL function.
55. packages.yml + dbt deps.
56. Documentation of a downstream data consumer (your AI report) in the lineage graph.
57. run = models only; build = models + tests + seeds + snapshots in dependency order.
58. Fail the pipeline on bad data before it reaches the marts or the AI.
59. unique, not_null, accepted_values, relationships.
60. A custom SQL file returning rule-violating rows; any rows returned = fail.
61. Rich assertions — value ranges, row counts, data types.
62. Temperature −50/60, humidity 0/100, or PM2.5 0/1000.
63. dbt_utils.unique_combination_of_columns (city_name + reading_date).
64. The newest loaded_at vs now; warns/errors if the data is stale.
65. warn (logs and continues) vs error (fails the run).
66. Groq llama-3.1-8b-instant.
67. mart_city_daily_summary (a tested dbt mart), not raw data.
68. Validated, pre-aggregated input gives coherent output; dbt tests guard quality every run.
69. fetch_rich_summary() (get + format data) and generate_full_report() (call the LLM).
70. So you can change where the data comes from without touching the generation logic.
71. Pro = flat-fee chat; API = per-token, separate billing; they share no credit.
72. ROW_NUMBER() OVER (PARTITION BY city, timestamp ORDER BY loaded_at DESC), keep rn=1.
73. Computes across related rows without collapsing them into a GROUP BY.
74. A named subquery (WITH ... AS) improving readability and modularity.
75. Upsert: update on key match, insert when no match — it drives incremental models.
76. Correlation between two numeric columns.
77. A generated complete date series, joined to find gaps/missing rows.
78. Filters on a window function result without needing a subquery (Snowflake).
79. `rows` — it's a reserved word; use cnt or rws instead.
80. ETL transforms before load; ELT loads raw then transforms in-warehouse.
81. It preserves the raw source of truth, versions transforms as SQL, and lets the warehouse do the compute.
82. PIPELINE_ROLE — least privilege, not ACCOUNTADMIN.
83. An Airflow pool (open_meteo_pool, 2 slots).
84. An isolated venv baked into a custom Airflow image, called by a DAG BashOperator.
85. TriggerDagRunOperator.
86. AUTO_SUSPEND=60 and AUTO_RESUME=TRUE.

---

*86 questions. Aim to clear 75+ cold before an interview. Anything you miss twice,
promote it to a note in docs/week3_notes.md and drill it separately.*
