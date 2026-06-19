import pandas as pd
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def transform_weather_data(df: pd.DataFrame) -> dict:
    if df.empty:
        logger.error("Empty dataframe received in transform step.")
        return{}
    
    df = df.copy()

    df["recorded_at"] = pd.to_datetime(df["recorded_at"])
    df["temperature_c"] = pd.to_numeric(df["temperature_c"], errors="coerce")
    df["humidity_pct"] = pd.to_numeric(df["humidity_pct"], errors="coerce")
    df["windspeed_kmh"] = pd.to_numeric(df["windspeed_kmh"], errors="coerce")
    df["weather_code"] = pd.to_numeric(df["weather_code"], errors="coerce").astype("int64")

    before = len(df)
    df = df.dropna(subset=["temperature_c"])
    logger.info(f"Dropped {before - len(df)} rows with null temperature values")

    df["date"] = df["recorded_at"].dt.date
    df["hour"] = df["recorded_at"].dt.hour

    df["date_sk"] = df["recorded_at"].dt.strftime("%Y%m%d").astype(int)

    city_lookup = df[["city", "country", "latitude", "longitude"]].drop_duplicates()
    logger.info(f"unique cities in this batch: {city_lookup['city'].to_list()}")

    fact_cols = [
        "city", "date_sk", "recorded_at", "temperature_c", "humidity_pct", "windspeed_kmh", "weather_code"
    ]
    df_fact = df[fact_cols].copy()
    df_fact.columns = [c.upper() for c in df_fact.columns]

    logger.info(f"transform completed. fact rows:{len(df_fact)}")

    return {
        "fact": df_fact
        ,"city_lookup": city_lookup
        ,"date_lookup": df["date_sk"].unique().tolist()    
    }


if __name__ == "__main__":
    logging.basicConfig(level = logging.INFO)

    sample = pd.DataFrame({
        "city": ["Mumbai","Delhi"],
        "country": ["India", "India"],
        "latitude": [19.07, 28.70],
        "longitude": [72.88, 77.10],
        "recorded_at": ["2026-06-13 06:00:00", "2026-06-13 06:00:00"],
        "temperature_c": [32.5, 39.8],
        "humidity_pct": [78.0, 42.0],
        "windspeed_kmh": [13.0, 18.5],
        "weather_code": [2, 3]
    })

    result = transform_weather_data(sample)
    print("Fact DataFrame:")
    print(result["fact"])
    print("\nCity lookup:")
    print(result["city_lookup"])