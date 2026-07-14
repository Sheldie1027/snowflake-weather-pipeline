import logging
import sys
from airflow.decorators import dag, task
from airflow.providers.http.sensors.http import HttpSensor
from datetime import datetime, timezone, timedelta
from airflow.models.baseoperator import chain
from alerts import alert_on_failure


sys.path.insert(0, "/opt/airflow/pipeline_src")

logger = logging.getLogger(__name__)

default_args = {
    "owner": "Sheldon",
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
    "on_failure_callback": alert_on_failure,
}

@dag(
    dag_id = "air_quality_pipeline_dag"
    ,schedule = "30 1 * * *"
    ,start_date = datetime(2026,6,26, tzinfo=timezone.utc)
    ,catchup = False
    ,default_args = default_args
    ,tags = ['week2', 'day4', 'production', 'air_quality']
)
def air_quality_pipeline():

    @task
    def get_run_id() -> str:
        return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    
    @task(pool="open_meteo_pool")
    def extract_air_quality():
        from extract_air_quality import extract_all_air_quality
        df = extract_all_air_quality()
        if df.empty:
            raise ValueError("No Air Quality data extracted")
        logger.info(f"Extracted {len(df)} rows")
        
        df["recorded_at"] = df["recorded_at"].astype(str)
        return df.to_dict(orient = "records")
    
    @task
    def load_raw_air_quality(records: list, pipeline_run_id: str):
        import pandas as pd
        from snowflake_client import get_connection, load_dataframe

        df = pd.DataFrame(records)
        df["recorded_at"] = pd.to_datetime(df["recorded_at"])
        df = df.dropna(subset=["pm2_5"])
        df["loaded_at"] = datetime.now(timezone.utc)
        df["pipeline_run_id"] = pipeline_run_id
        df.columns = [c.upper() for c in df.columns]

        conn = get_connection()
        success, nrows = load_dataframe(
            df = df
            ,table_name = "RAW_AIR_QUALITY"
            ,database = "WEATHER_DB"
            ,schema = "RAW"
            ,conn =conn
        )
        conn.close()

        if not success:
            raise RuntimeError("Failed to load Air quality data to RAW table")
        logger.info(f"loaded {nrows} rows to RAW_AIR_QUALITY table")

    run_id = get_run_id()
    raw = extract_air_quality()
    load_raw_air_quality(raw, run_id)

air_quality_pipeline()