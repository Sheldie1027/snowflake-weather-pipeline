import logging 
import sys
from airflow.decorators import dag, task
from airflow.providers.http.sensors.http import HttpSensor
from airflow.models import Variable
from airflow.models.baseoperator import chain
from datetime import datetime, timezone, timedelta
from airflow.operators.trigger_dagrun import TriggerDagRunOperator
from alerts import alert_on_failure


sys.path.insert(0, "/opt/airflow/pipeline_src")

logger = logging.getLogger(__name__)

default_args = {
    "owner": "Sheldon"
    ,"retries" : 2
    ,"retry_delay" : timedelta(minutes=2)
    ,"retry_exponential_backoff" : True
    ,"on_failure_callback" : alert_on_failure
}

@dag(
    dag_id = 'weather_pipeline_dag'
    ,schedule = '30 1 * * *'
    ,start_date = datetime(2026, 6, 26, tzinfo=timezone.utc)
    ,catchup = False
    ,default_args = default_args
    ,tags = ['week2', 'day4', 'production', 'weather']
)
def weather_pipeline():
    wait_for_api = HttpSensor(
        task_id = "wait_for_open_meteo_api"
        ,http_conn_id = "open_meteo_api"
        ,endpoint = "/v1/forecast?latitude=19.07&longitude=72.88&hourly=temperature_2m"
        ,method = "GET"
        ,response_check = lambda response: response.status_code == 200
        ,poke_interval = 15
        ,timeout = 180
        ,mode = "reschedule"
    )

    @task(pool="open_meteo_pool")
    def weather_extract():
        from extract import extract_all_cities
        df = extract_all_cities()
        if df.empty:
            raise ValueError("No Data extracted")
        
        logger.info(f"Extracted {len(df)} rows")

        df["recorded_at"] = df["recorded_at"].astype(str)
        return df.to_dict(orient="records")
    
    @task
    def load_raw(records: list, pipeline_run_id:str):
        import pandas as pd
        from snowflake_client import get_connection, load_dataframe

        df = pd.DataFrame(records)
        df["recorded_at"] = pd.to_datetime(df["recorded_at"])
        df = df.dropna(subset=["temperature_c"])
        df["loaded_at"] = datetime.now(timezone.utc)
        df["pipeline_run_id"] = pipeline_run_id
        df.columns = [c.upper() for c in df.columns]

        conn = get_connection()
        success, nrows = load_dataframe(
            df = df
            ,table_name = "RAW_WEATHER_API"
            ,database  = "WEATHER_DB"
            ,schema = "RAW"
            ,conn = conn
        )
        conn.close()

        if not success:
            raise RuntimeError("Failed to load to RAW")
        
        logger.info(f"Loaded {nrows} to RAW_WEATHER_API table")
        return nrows
    
    @task
    def load_fact(pipeline_run_id : str):
        from snowflake_client import get_connection, run_query

        conn = get_connection()
        sql = f"""
            INSERT INTO WEATHER_DB.MARTS.FACT_WEATHER_READINGS
                (city_sk, date_sk, weather_code_sk, recorded_at,
                 temperature_c, humidity_pct, windspeed_kmh, pipeline_run_id)
            SELECT
                c.city_sk,
                TO_NUMBER(TO_VARCHAR(DATE(r.recorded_at), 'YYYYMMDD')) AS date_sk,
                COALESCE(w.code_sk, 1) AS weather_code_sk,
                r.recorded_at,
                r.temperature_c,
                r.humidity_pct,
                r.windspeed_kmh,
                '{pipeline_run_id}' AS pipeline_run_id
            FROM WEATHER_DB.RAW.RAW_WEATHER_API r
            JOIN WEATHER_DB.MARTS.DIM_CITY c
                ON r.city = c.city_nk AND c.is_current = TRUE
            LEFT JOIN WEATHER_DB.MARTS.DIM_WEATHER_CODE w
                ON r.weather_code = w.code_value
            WHERE r.pipeline_run_id = '{pipeline_run_id}'
        """

        run_query(sql, conn)
        conn.close()
        logger.info("Loaded data to FACT table")
    

    @task
    def generate_ai_summary():
        from ai_summary import generate_full_report
        summary = generate_full_report()
        logger.info(f"AI Summary: {summary[:200]}...")
        return summary
    
    @task
    def get_run_id() -> str:
        return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    
    trigger_dbt = TriggerDagRunOperator(
        task_id="trigger_dbt_transform",
        trigger_dag_id="dbt_transform_dag",
    )
    

    pipeline_run_id = get_run_id()
    raw_data = weather_extract()
    rows_loaded = load_raw(raw_data, pipeline_run_id)
    fact_loaded = load_fact(pipeline_run_id)
    summary = generate_ai_summary()

    from airflow.models.baseoperator import chain
    chain (wait_for_api, raw_data, rows_loaded, fact_loaded, summary, trigger_dbt)

weather_pipeline()