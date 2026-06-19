import logging
from datetime import datetime, timezone
from extract import extract_all_cities
from transform import transform_weather_data
from snowflake_client import get_connection, run_query, load_dataframe
from ai_summary import generate_full_report

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("docs/pipeline.log")
    ]
)
logger = logging.getLogger(__name__)


def load_fact_data(df_fact, conn, run_id: str):

    # Fetch city SK mappings from Snowflake
    city_map_query = """
        SELECT 
            city_nk
            ,city_sk
        FROM WEATHER_DB.MARTS.DIM_CITY
        WHERE is_current = TRUE
    """
    city_rows = run_query(city_map_query, conn)
    city_map = {row[0]: row[1] for row in city_rows}

    # Add surrogate keys
    import pandas as pd
    df = df_fact.copy()
    df["CITY_SK"] = df["CITY"].map(city_map)
    df["PIPELINE_RUN_ID"] = run_id

    # Fetch weather code SK mappings
    code_map_query = """
        SELECT 
            code_value
            ,code_sk
        FROM WEATHER_DB.MARTS.DIM_WEATHER_CODE
    """
    code_rows = run_query(code_map_query, conn)
    code_map = {row[0]: row[1] for row in code_rows}

    df["WEATHER_CODE_SK"] = df["WEATHER_CODE"].map(code_map).fillna(1).astype(int)

    # Select only columns that match FACT table
    fact_final = df[[
        "CITY_SK", "DATE_SK", "WEATHER_CODE_SK",
        "RECORDED_AT", "TEMPERATURE_C", "HUMIDITY_PCT",
        "WINDSPEED_KMH", "PIPELINE_RUN_ID"
    ]].copy()

    fact_final = fact_final.rename(columns={"DATE_SK": "DATE_SK"})
    fact_final.columns = [
        "CITY_SK", "DATE_SK", "WEATHER_CODE_SK",
        "RECORDED_AT", "TEMPERATURE_C", "HUMIDITY_PCT",
        "WINDSPEED_KMH", "PIPELINE_RUN_ID"
    ]

    return load_dataframe(
        df=fact_final,
        table_name="FACT_WEATHER_READINGS",
        database="WEATHER_DB",
        schema="MARTS",
        conn=conn
    )


def run_pipeline():
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    logger.info(f"=== PIPELINE START | Run ID: {run_id} ===")

    # Step 1: Extract
    logger.info("STEP 1: Extracting data from Open-Meteo API...")
    df_raw = extract_all_cities()
    if df_raw.empty:
        logger.error("Extraction failed. Exiting.")
        return

    # Step 2: Transform
    logger.info("STEP 2: Transforming data...")
    transformed = transform_weather_data(df_raw)
    if not transformed:
        logger.error("Transform failed. Exiting.")
        return

    # Step 3: Load to RAW
    logger.info("STEP 3: Loading raw data to Snowflake...")
    conn = get_connection()
    import pandas as pd
    df_for_raw = df_raw.copy()
    df_for_raw["PIPELINE_RUN_ID"] = run_id
    df_for_raw.columns = [c.upper() for c in df_for_raw.columns]

    success, nrows = load_dataframe(
        df=df_for_raw,
        table_name="RAW_WEATHER_API",
        database="WEATHER_DB",
        schema="RAW",
        conn=conn
    )
    logger.info(f"RAW load: {nrows} rows")

    # Step 4: Load to FACT
    logger.info("STEP 4: Loading to FACT table...")
    load_fact_data(transformed["fact"], conn, run_id)
    conn.close()

    # Step 5: AI Summary
    logger.info("STEP 5: Generating AI summary...")
    summary = generate_full_report()
    logger.info(f"AI Summary:\n{summary}")

    with open("docs/ai_summary_output.txt", "w") as f:
        f.write(f"Run ID: {run_id}\n")
        f.write(f"Generated: {datetime.now(timezone.utc)}\n\n")
        f.write(summary)

    logger.info(f"=== PIPELINE COMPLETE | Run ID: {run_id} ===")


if __name__ == "__main__":
    run_pipeline()