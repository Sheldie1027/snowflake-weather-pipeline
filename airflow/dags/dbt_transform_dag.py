from airflow.decorators import dag
from airflow.operators.bash import BashOperator
from datetime import datetime, timezone, timedelta
from alerts import alert_on_dbt_failure

DBT_PROJECT_DIR = "/opt/airflow/dbt/weather_dbt"
DBT_PROFILES_DIR = "/opt/airflow/.dbt"
DBT_BIN = "/opt/airflow/dbt_venv/bin/dbt"

default_args = {
    "owner" : "Sheldon"
    ,"retries": 1
    ,"retry_delay": timedelta(minutes=2)
    ,"on_failure_callback" : alert_on_dbt_failure
}


@dag(
    dag_id="dbt_transform_dag",
    schedule=None,
    start_date=datetime(2026, 7, 10, tzinfo=timezone.utc),
    catchup=False,
    default_args=default_args,
    tags=["week3", "dbt", "transform"],
)
def dbt_transform():

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=(
            f"DBT_PRIVATE_KEY_PATH=/opt/airflow/config/rsa_key.pem "
            f"{DBT_BIN} run "
            f"--project-dir {DBT_PROJECT_DIR} "
            f"--profiles-dir {DBT_PROFILES_DIR} "
            f"--target prod"
        ),
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            f"DBT_PRIVATE_KEY_PATH=/opt/airflow/config/rsa_key.pem "
            f"{DBT_BIN} test "
            f"--project-dir {DBT_PROJECT_DIR} "
            f"--profiles-dir {DBT_PROFILES_DIR} "
            f"--target prod"
        ),
    )

    dbt_freshness = BashOperator(
        task_id="dbt_source_freshness",
        bash_command=" ".join([
            "DBT_PRIVATE_KEY_PATH=/opt/airflow/config/rsa_key.pem",
            DBT_BIN, "source", "freshness",
            "--project-dir", DBT_PROJECT_DIR,
            "--profiles-dir", DBT_PROFILES_DIR,
            "--target", "prod",
        ]),
    )

    dbt_freshness >> dbt_run >> dbt_test


dbt_transform()