import logging
from datetime import datetime, timezone
from extract import extract_all_cities
from snowflake_client import get_connection, load_dataframe
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


def run_pipeline():
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    logger.info(f"=== PIPELINE START | Run ID: {run_id} ===")

    logger.info("STEP 1: Extracting data from Open-Meteo API...")
    df_raw = extract_all_cities()
    if df_raw.empty:
        logger.error("Extraction failed. Exiting.")
        return

    logger.info("STEP 2: Loading raw data to Snowflake...")
    conn = get_connection()
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
    conn.close()

    logger.info("STEP 3: Generating AI summary...")
    summary = generate_full_report()
    logger.info(f"AI Summary:\n{summary}")

    with open("docs/ai_summary_output.txt", "w") as f:
        f.write(f"Run ID: {run_id}\n")
        f.write(f"Generated: {datetime.now(timezone.utc)}\n\n")
        f.write(summary)

    logger.info(f"=== PIPELINE COMPLETE | Run ID: {run_id} ===")


if __name__ == "__main__":
    run_pipeline()