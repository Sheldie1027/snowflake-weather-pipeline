import logging
from datetime import datetime, timezone
from cities import CITIES
from extract import fetch_weather_for_city
from snowflake_client import get_connection, load_dataframe

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

START_DATE = "2026-05-29"      
END_DATE = "2026-07-13"        
TARGET_CITY = "Chennai"


def run_backfill():
    run_id = "backfill_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    city = next(c for c in CITIES if c["name"] == TARGET_CITY)

    logger.info("=== BACKFILL START | %s | %s to %s ===", TARGET_CITY, START_DATE, END_DATE)

    df = fetch_weather_for_city(city, start_date=START_DATE, end_date=END_DATE)

    if df.empty:
        logger.error("No data returned. Check the archive endpoint supports this range.")
        return

    df["PIPELINE_RUN_ID"] = run_id
    df.columns = [c.upper() for c in df.columns]

    conn = get_connection()
    success, nrows = load_dataframe(
        df=df,
        table_name="RAW_WEATHER_API",
        database="WEATHER_DB",
        schema="RAW",
        conn=conn,
    )
    conn.close()

    if success:
        logger.info("=== BACKFILL COMPLETE | %s rows loaded for %s ===", nrows, TARGET_CITY)
    else:
        logger.error("Backfill failed")


if __name__ == "__main__":
    run_backfill()