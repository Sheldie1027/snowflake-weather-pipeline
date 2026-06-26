from airflow.decorators import dag, task
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
from datetime import datetime, timezone


@dag(
    dag_id = 'snowflake_test_dag'
    ,schedule = None
    ,start_date = datetime(2026, 6, 22, tzinfo = timezone.utc)
    ,catchup = False
    ,tags = ['week2', 'day2']
)
def snowflake_test():
    check_connection = SnowflakeOperator(
        task_id = 'check_Snowflake_Connection'
        ,snowflake_conn_id = 'snowflake_default'
        ,sql = "select current_user(), current_database(),current_timestamp();"
    )

    count_rows = SnowflakeOperator(
        task_id = 'count_fact_table_rows'
        ,snowflake_conn_id = 'snowflake_default'
        ,sql = "select count(*) as no_of_rows_fact from weather_db.marts.fact_weather_readings;"
    )

    check_connection >> count_rows

snowflake_test()