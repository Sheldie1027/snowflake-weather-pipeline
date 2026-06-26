from airflow.decorators import dag, task
from airflow.models import Variable
from datetime import datetime, timezone, timedelta
import logging

logger = logging.getLogger(__name__)


default_args = {
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
    "retry_exponential_backoff": True,
    "on_failure_callback": lambda context: logger.error(
        f"Task {context['task_instance'].task_id} failed on attempt "
        f"{context['task_instance'].try_number}"
    ),
}

@dag(
    dag_id="scheduled_weather_dag",
    schedule="30 1 * * *",   # 7am IST daily
    start_date=datetime(2026, 6, 22, tzinfo=timezone.utc),
    catchup=False,
    default_args=default_args,
    tags=["week2", "day3"],
)
def scheduled_weather_pipeline():

    @task(retries=3)
    def check_api_health():
        import requests
        try:
            response = requests.get(
                "https://api.open-meteo.com/v1/forecast",
                params={"latitude": 19.07, "longitude": 72.88, "hourly": "temperature_2m"},
                timeout=10
            )
            response.raise_for_status()
            logger.info("API health check passed")
            return True
        except Exception as e:
            logger.error(f"API health check failed: {e}")
            raise

    @task
    def extract_data(api_healthy: bool):
        if not api_healthy:
            raise ValueError("Cannot extract — API is not healthy")
        logger.info("Extracting weather data...")
        # placeholder for now — real extract comes in the full pipeline DAG
        return {"rows_extracted": 576, "cities": ["Mumbai", "Bangalore", "Delhi"]}

    @task
    def log_summary(extract_result: dict):
        logger.info(f"Pipeline summary:")
        logger.info(f"  Rows extracted: {extract_result['rows_extracted']}")
        logger.info(f"  Cities: {extract_result['cities']}")

    health = check_api_health()
    result = extract_data(health)
    log_summary(result)

scheduled_weather_pipeline()