dbt tests turn data quality from a hope into an assertion. Every run, dbt verifies my assumptions: keys are unique, foreign keys resolve, values are in range, cities are known.

If the source data drifts or the pipeline breaks, tests catch it before bad data reaches the AI summary or any dashboard. This is the core advantage of dbt over raw INSERT...SELECT.

seeds are for small, static, version-controlled reference data — not for large or frequently-changing data (that belongs in your pipeline).

change the model's structure (add a column, change the key), and you must use '--full-refresh' once to rebuild from scratch. Change only data, and normal incremental runs suffice.

Week 1: I hand-wrote SCD Type 2 — a manual UPDATE to expire the old row, then an INSERT for the new version, managing valid_from/valid_to/is_current myself. dbt snapshots do all of this automatically with strategy='check' — I write a SELECT, dbt manages dbt_valid_from, dbt_valid_to, and dbt_scd_id. Same dimensional modelling concept, automated.


Modern ELT, fully orchestrated:

EXTRACT + LOAD: Airflow runs Python (API to RAW in Snowflake)
TRANSFORM: Airflow triggers a separate dbt DAG (RAW to staging to marts, with tests)
Ingestion DAG chains to the dbt DAG via TriggerDagRunOperator
dbt runs in an isolated venv inside the container to avoid dependency conflicts with Airflow
This separates imperative E+L (Python) from declarative T (dbt) — the defining pattern of the modern data stack.