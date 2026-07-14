# Performance & Cost Analysis

**Project:** Weather Intelligence Pipeline
**Warehouse:** `COMPUTE_WH` (X-Small)
**Analysis date:** 14 July 2026
**Data source:** `SNOWFLAKE.ACCOUNT_USAGE` (query history, warehouse metering, storage metrics)

---

## 1. Cost baseline

**Total compute consumed over the project's lifetime: 8.42 credits** (≈ $25 at
standard Standard-edition pricing). Across roughly six weeks of near-daily
pipeline runs, that averages well under a credit per active day.

### Daily consumption (recent)

| Date | Credits |
|---|---|
| 2026-07-14 | 0.8223 |
| 2026-07-13 | 0.7445 |
| 2026-07-12 | 0.4818 |
| 2026-07-11 | 0.0512 |
| 2026-07-10 | 0.4886 |
| 2026-07-09 | 0.9401 |
| 2026-07-08 | 0.1346 |
| 2026-06-28 | 0.1962 |
| 2026-06-27 | 0.0679 |
| 2026-06-17 | 0.0596 |
| 2026-06-11 | 0.6363 |
| **2026-06-09** | **3.7194** |
| 2026-06-08 | 0.0003 |

### Finding: one day accounts for 44% of all compute ever used

**2026-06-09 consumed 3.72 credits — more than the next four highest days
combined, and 44% of the project's total 8.42.**

That was the initial environment build: creating the database, schemas, and
tables, seeding dimensions, and running the first full data loads. It is a
one-off setup cost, not a recurring operational cost.

**This is the single most important number in this analysis**, because it means
the headline figure is misleading. Excluding the setup day, steady-state
operation has cost **4.70 credits over ~6 weeks — roughly 0.11 credits per day.**

The lesson generalises: when profiling cost, separate **one-off provisioning**
from **steady-state operation**, or you will size and budget against a number
that does not reflect how the system actually behaves.

### Cost distribution is bursty, not smooth

Daily credits swing from 0.0003 to 0.94 on active days, with several days at
zero. This is expected and correct: `AUTO_SUSPEND = 60` means the warehouse only
bills while it is actually executing. Idle days cost nothing. Days with heavy
dbt development cost more than days with a single scheduled run.

---

## 2. Where the compute goes

Compute by pipeline stage (last 14 days):

| Stage | Queries | Total seconds | Avg seconds |
|---|---|---|---|
| other | 3,912 | 959.2 | 0.25 |
| dbt: model build | 347 | 308.2 | 0.89 |
| Python: RAW load | 71 | 87.8 | 1.24 |
| AI report read | 286 | 81.8 | 0.29 |
| dbt: incremental merge | 65 | 70.1 | 1.08 |

### Finding: query *count* and query *cost* are decoupled

The "other" bucket dominates by volume — 3,912 queries — but each averages only
0.25 seconds. These are metadata operations: dbt's `SHOW`/`DESCRIBE` calls,
connection handshakes, transaction control. They are numerous and individually
trivial.

**dbt model builds are the real compute driver.** At 347 queries and 0.89s
average, they consume 308 seconds — a third of total runtime from under a tenth
of the query volume.

The AI report, despite 286 reads, costs 81.8 seconds total. The decision to have
the LLM read a **pre-aggregated mart** rather than query raw data directly means
each read is a trivial four-row scan. That architectural choice is visible in
the cost profile.

### Finding: the most expensive queries are not pipeline queries

The slowest queries in the account are `ACCOUNT_USAGE` introspection queries —
including the ones written for *this analysis* (6.66s scanning 130 MB, 4.25s
scanning 632 MB). Two Snowflake-internal `anomaly_insights` procedures took 19.8s
and 12.5s.

**The actual pipeline's heaviest query is a dbt incremental merge at 3.58
seconds, scanning 0.13 MB across 1 of 1 partitions.**

That is worth stating plainly: **there is no performance problem to solve.** The
pipeline's workload is trivially small for the warehouse it runs on.

---

## 3. Pruning and spilling

| Metric | Finding |
|---|---|
| **Spilling to local storage** | 0 on every pipeline query |
| **Spilling to remote storage** | 0 across the board |
| **Partitions scanned (dbt merge)** | 1 of 1 |
| **Bytes scanned (dbt merge)** | 0.13 MB |

Two `ACCOUNT_USAGE` queries spilled ~79 MB to local storage — but those are
introspection queries against Snowflake's own multi-gigabyte metadata views, not
pipeline workload.

**No pipeline query has ever spilled.** The warehouse has never exhausted memory.
Pruning is a non-question at this volume: the fact table occupies a single
micro-partition, so there is nothing to prune.

---

## 4. Storage

| Schema | Table | Active MB | Time Travel MB | Fail-safe MB |
|---|---|---|---|---|
| MARTS | FACT_WEATHER_READINGS | 0.25 | 1.04 | 0.33 |
| DBT_CI | FCT_WEATHER_READINGS | 0.14 | 0.83 | 0 |
| DBT_DEV | FCT_WEATHER_READINGS | 0.13 | 0 | 0 |
| RAW | LINK_WEATHER_READING | 0.08 | 0 | 0 |
| RAW | SAT_WEATHER_READINGS | 0.08 | 0 | 0 |
| DBT_DEV | FCT_AIR_QUALITY_READINGS | 0.06 | 0 | 0 |
| RAW | RAW_AIR_QUALITY | 0.03 | 0 | 0.06 |
| RAW | RAW_WEATHER_API | 0.02 | 0 | 0 |
| DBT_DEV | MART_CITY_DAILY_SUMMARY | 0.01 | 0 | 0 |

**Total active storage across the entire database is under 1 MB.** Storage cost
is effectively zero and will remain so for years at the current ingestion rate.

### Finding: Time Travel costs 4× more than the data itself

`MARTS.FACT_WEATHER_READINGS` holds 0.25 MB of active data but carries **1.04 MB
of Time Travel and 0.33 MB of Fail-safe** — over five times the live data.

The cause is churn. That table was repeatedly rebuilt during development, and
Snowflake retains every prior version for the retention window. The same pattern
appears in `DBT_CI.FCT_WEATHER_READINGS` (0.14 MB active, 0.83 MB Time Travel) —
which is expected, since CI rebuilds it on every pull request.

At this scale it is a rounding error. **At terabyte scale it would be a
significant and easily-overlooked line item**, and a frequently-rebuilt table
with a long retention window is exactly where that cost hides. Worth knowing that
`DATA_RETENTION_TIME_IN_DAYS` can be lowered on high-churn, easily-rebuilt tables
(such as a CI schema) where recovery is not needed.

---

## 5. Decisions made

**`AUTO_SUSPEND = 60`, `AUTO_RESUME = TRUE`** — the highest-leverage cost setting
available. Snowflake bills for warehouse *uptime*, not query complexity, so an
idle running warehouse costs exactly the same as a busy one. Suspending after 60
seconds of inactivity is why zero-activity days cost nothing.

**Warehouse tagging** — `cost_center` and `environment` tags applied to
`COMPUTE_WH`, so consumption can be attributed rather than appearing as
untagged spend.

**Resource monitor with graduated triggers** — notify at 75% and 90% of quota,
suspend at 100% (allowing running queries to finish), suspend immediately at
110%. Nothing previously prevented a runaway query from consuming the remaining
credit balance.

**The AI reads a pre-aggregated mart, not raw data** — an architectural decision
made for data-quality reasons (the LLM only sees tested data), which also turns
out to be the right cost decision: each report read is a four-row scan.

---

## 6. Decisions deliberately NOT made

This section matters more than the previous one. Every optimisation below was
evaluated against real measurements and **rejected**, because at this scale the
cost exceeds the benefit.

### Warehouse upsizing — rejected

Bigger warehouses are not always more expensive: a Medium (4 credits/hr) that
finishes in 1 minute costs less than an X-Small (1 credit/hr) that takes 8. The
decision hinges on whether queries are memory- or compute-constrained.

**Measured: zero spilling on every pipeline query; the heaviest is 3.58 seconds.**
There is no memory pressure and no meaningful runtime to reclaim. X-Small is
correct, and this was verified rather than assumed.

### Clustering keys — rejected

Clustering co-locates data in micro-partitions to improve pruning, and would be
the natural choice for a large fact table queried by date range.

**Measured: `fct_weather_readings` scans 1 of 1 partitions at 0.13 MB.** The
table fits in a single micro-partition — there is nothing to prune. Clustering
also incurs an ongoing automatic reclustering cost, and Snowflake's guidance is
that it only pays off above roughly 1 TB. Adding a clustering key here would cost
money for zero benefit.

### Materialized views — rejected

A materialized view would pre-compute the daily summary. But `mart_city_daily_summary`
is already a materialised dbt table, rebuilt on a schedule — a materialized view
would duplicate that with extra maintenance cost and no query-pattern justification.

### Lowering Time Travel retention — rejected (for now)

`DBT_CI` carries 0.83 MB of Time Travel on a table rebuilt every pull request, and
that data will never be recovered. Reducing `DATA_RETENTION_TIME_IN_DAYS` to 0 on
the CI schema would eliminate it — but the saving is under a megabyte. Noted as
the correct move *at scale*, not worth the change now.

**The general principle:** knowing when *not* to optimise is the harder skill.
Every one of these would look like diligence on a CV and would in fact be waste.

---

## 7. What would change at 10,000× scale

At ~50 million rows (roughly 10,000× current volume), four things change:

**Clustering becomes correct.** `fct_weather_readings` would span thousands of
micro-partitions, and date-range pruning would become the dominant cost factor.
Clustering on `recorded_at` would then pay for its reclustering overhead.

**CI must stop rebuilding everything.** The current CI job runs a full `dbt build`
on every pull request. At scale this becomes untenable — the fix is `--defer` with
`state:modified+`, so CI builds only changed models plus their downstream
dependents, resolving unchanged refs against production rather than rebuilding them.

**Warehouse sizing needs re-evaluation against spilling.** The right trigger is
not "it feels slow" but `bytes_spilled_to_remote_storage > 0`, which is the
unambiguous signal that memory has been exhausted and a larger warehouse would
be *cheaper*, not just faster.

**CI needs its own warehouse.** Currently CI, dev, and production all share
`COMPUTE_WH`. At scale, a long CI build would contend with the production
pipeline. Separate warehouses would isolate them and make cost attribution exact.

**Time Travel becomes a real line item.** A high-churn fact table carrying 4× its
active size in Time Travel is invisible at 1 MB and material at 1 TB.

---

## 8. Summary

| Metric | Value |
|---|---|
| Total compute, project lifetime | 8.42 credits (≈ $25) |
| One-off setup (2026-06-09) | 3.72 credits — **44% of all usage** |
| Steady-state operation | ~0.11 credits/day |
| Total active storage | < 1 MB |
| Heaviest pipeline query | 3.58s, 0.13 MB, 1 partition |
| Queries that spilled to disk | **0** |
| Optimisations applied | AUTO_SUSPEND, tagging, resource monitor |
| Optimisations evaluated and rejected | Upsizing, clustering, materialized views |

The pipeline is correctly sized for its workload. The most valuable outcome of
this analysis was not a speedup — it was establishing that **no speedup is
warranted**, and understanding precisely which measurements would change that
conclusion at scale.
