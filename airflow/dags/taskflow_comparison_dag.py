from airflow.decorators import dag, task
from airflow.operators.python import PythonOperator
from datetime import datetime, timezone

# ── CLASSIC STYLE (old way) ───────────────────────────────────────────────────
# Problems: verbose, manual XCom push/pull, harder to read

def _extract(**context):
    data = {"rows": 100, "source": "api"}
    # Manual XCom push
    context["ti"].xcom_push(key="extract_result", value=data)

def _load(**context):
    # Manual XCom pull - you have to know the exact task_id and key
    data = context["ti"].xcom_pull(task_ids="extract_task", key="extract_result")
    print(f"Loading {data['rows']} rows from {data['source']}")

# ── TASKFLOW STYLE (modern way) ───────────────────────────────────────────────
# Benefits: clean, automatic XCom via return values, reads like normal Python

@dag(
    dag_id="taskflow_comparison_dag",
    schedule=None,
    start_date=datetime(2026, 6, 22, tzinfo=timezone.utc),
    catchup=False,
    tags=["week2", "day3"],
)
def taskflow_pipeline():

    @task
    def extract() -> dict:
        # Just return the value - XCom handled automatically
        return {"rows": 100, "source": "api"}

    @task
    def transform(data: dict) -> dict:
        # Receive previous task's return value as a parameter
        data["rows_transformed"] = data["rows"] * 2
        return data

    @task
    def load(data: dict):
        print(f"Loading {data['rows_transformed']} rows from {data['source']}")

    # Clean linear flow - reads like normal Python
    raw = extract()
    transformed = transform(raw)
    load(transformed)

taskflow_pipeline()