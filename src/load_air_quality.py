import logging
from datetime import datetime, timezone
from snowflake_client import get_connection, load_dataframe
from extract_air_quality import extract_all_air_quality

logging.basicConfig(level = logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

def run_air_quality_pipeline():
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    logger.info(f"=== AIR QUALITY PIPELINE START | Run ID: {run_id} ===")
    logger.info ("Extracting air quality data...")
    df = extract_all_air_quality()
    if df.empty:
        logger.error("No data extracted")
        return
    
    before = len(df)
    df = df.dropna(subset=["pm2_5"])
    logger.info(f"Dropped {before - len(df)} null rows")

    df["loaded_at"] = datetime.now(timezone.utc)
    df["pipeline_run_id"] = run_id

    df.columns = [c.upper() for c in df.columns]

    conn = get_connection()
    success, nrows = load_dataframe(
        df =df
        ,table_name="RAW_AIR_QUALITY"
        ,database = "WEATHER_DB"
        ,schema="RAW"
        ,conn=conn
    )
    conn.close()

    if success:
        logger.info(f"=== AIR QUALITY PIPELINE COMPLETE | {nrows} rows loaded ===")
    else:
        logger.error("Pipeline Failed")

if __name__ == "__main__":
    run_air_quality_pipeline()