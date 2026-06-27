from airflow.decorators import dag, task, task_group
from datetime import datetime, timezone

@dag(
    dag_id="task_groups_dag",
    schedule=None,
    start_date=datetime(2026, 6, 22, tzinfo=timezone.utc),
    catchup=False,
    tags=["week2", "day3"],
)
def grouped_pipeline():

    @task
    def start_pipeline():
        print("Pipeline starting...")
        return True

    @task_group(group_id="extraction_group")
    def extraction_tasks():

        @task
        def extract_weather():
            print("Extracting weather data...")
            return {"weather_rows": 192}

        @task
        def extract_air_quality():
            print("Extracting air quality data...")
            return {"aq_rows": 192}

        weather = extract_weather()
        air = extract_air_quality()
        return weather, air

    @task_group(group_id="load_group")
    def load_tasks(weather_data, aq_data):

        @task
        def load_weather(data: dict):
            print(f"Loading {data['weather_rows']} weather rows")

        @task
        def load_air_quality(data: dict):
            print(f"Loading {data['aq_rows']} air quality rows")

        load_weather(weather_data)
        load_air_quality(aq_data)

    @task
    def finish_pipeline():
        print("Pipeline complete!")

    # Wire everything together
    started = start_pipeline()
    weather_result, aq_result = extraction_tasks()
    load_tasks(weather_result, aq_result)
    finish_pipeline()

grouped_pipeline()