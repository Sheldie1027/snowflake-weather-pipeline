The silent failure.
Chennai was absent from the daily summary mart for weeks while every dbt test passed. Root cause: the weather and air quality extract modules each owned a copy of the city list, and they drifted. The mart joins FROM weather, so a city with air quality but no weather never entered the join — no error, no failing test, no missing-data warning. It simply wasn't there.

Two fixes, at two levels:

Root cause — a single source of truth for the city list (src/cities.py), imported by both extract modules. Drift is now structurally impossible.
Systemic guard — COMPLETENESS tests. My entire suite validated the rows that existed; nothing asserted that expected rows exist. Validity is not completeness. Added singular tests asserting every configured city is present and recently updated.

The backfill itself surfaced a second lesson: incremental models only process rows newer than the current watermark, so backfilled (older) rows are silently skipped. A backfill must be followed by --full-refresh on downstream incremental models.