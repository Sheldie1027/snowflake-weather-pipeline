import logging
import pandas as pd
from datetime import datetime, timezone
from snowflake_client import get_connection , load_dataframe
from extract import extract_all_cities

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

def prepare_for_load(df: pd.DataFrame, run_id: str) -> pd.DataFrame:
    df = df.copy()
    before = len(df)
    df = df.dropna(subset= ["temperature_c"])
    logger.info(f"Dropped {before - len(df)} null rows")

    df["loaded_at"] = datetime.now(timezone.utc)
    df["pipeline_run_id"] = run_id

    df.columns = [c.upper() for c in df.columns]

    return df


def main():
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    logger.info(f"Pipeline run id: {run_id}")

    logger.info("Starting Extraction...")
    df_raw = extract_all_cities()

    if df_raw.empty:
        logger.error(f"No data ectracted. Exiting")
        return
    
    logger.info("Preparing data for load...")
    df_ready = prepare_for_load(df_raw, run_id)

    logger.info(f"Rows ready to load {len(df_ready)}")
    logger.info(f"Columns {df_ready.columns.to_list()}")

    logger.info("Loading data to Snowflake...")
    conn = get_connection()

    success, nrows = load_dataframe(
        df = df_ready
        ,table_name= "RAW_WEATHER_API"
        ,database= "WEATHER_DB"
        ,schema= "RAW"
        ,conn= conn
    )

    if success:
        logger.info(f"Loading of data is completed. {nrows} loaded successfully")
    else:
        logger.info("Pipeline failed during load step.")


if __name__ == "__main__":
    main()

