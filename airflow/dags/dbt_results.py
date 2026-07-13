import json
import logging

logger = logging.getLogger(__name__)

RUN_RESULTS = "/opt/airflow/dbt/weather_dbt/target/run_results.json"


def summarise_dbt_failures(path: str = RUN_RESULTS) -> str:
    try:
        with open(path) as f:
            results = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        return f"Could not read dbt run results: {e}"

    failures = [
        r for r in results.get("results", [])
        if r.get("status") in ("error", "fail")
    ]

    if not failures:
        return ""

    lines = [f"{len(failures)} dbt node(s) failed:\n"]
    for r in failures:
        node = r.get("unique_id", "unknown")
        status = r.get("status")
        msg = (r.get("message") or "").strip()
        lines.append(f"  [{status.upper()}] {node}")
        if msg:
            lines.append(f"      {msg[:200]}")

    return "\n".join(lines)