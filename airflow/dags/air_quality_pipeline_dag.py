from airflow.decorators import dag, task
from airflow.providers.http.sensors.http import HttpSensor
from datetime import datetime, timezone, timedelta
from airflow.models.baseoperator import chain
import logging
import sys

sys.path.insert(0, "/opt/airflow/pipeline_src")

logger = logging.getLogger(__name__)

default_args = {
    "retries" : 2
    ,"retry_delay" : timedelta(minutes=2)
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

    @task
    def load_fact_air_quality(pipeline_run_id : str):
        from snowflake_client import get_connection, run_query

        conn = get_connection()
        sql = f"""
            INSERT INTO WEATHER_DB.MARTS.FACT_AIR_QUALITY_READINGS
                (city_sk, date_sk, recorded_at, pm2_5, uv_index,
                 carbon_monoxide, pipeline_run_id)
            SELECT
                c.city_sk,
                TO_NUMBER(TO_VARCHAR(DATE(r.recorded_at), 'YYYYMMDD')) AS date_sk,
                r.recorded_at,
                r.pm2_5,
                r.uv_index,
                r.carbon_monoxide,
                '{pipeline_run_id}' AS pipeline_run_id
            FROM WEATHER_DB.RAW.RAW_AIR_QUALITY r
            JOIN WEATHER_DB.MARTS.DIM_CITY c
                ON r.city = c.city_nk AND c.is_current = TRUE
            WHERE r.pipeline_run_id = '{pipeline_run_id}'
        """

        run_query(sql, conn)
        conn.close()
        logger.info("Loaded air quality data to fact table")

    run_id = get_run_id()
    raw = extract_air_quality()
    load_raw_result = load_raw_air_quality(raw, run_id)
    load_fact_result = load_fact_air_quality(run_id)

    chain(load_raw_result,load_fact_result)

air_quality_pipeline()