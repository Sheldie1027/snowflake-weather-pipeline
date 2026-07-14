import requests
import pandas as pd
import logging
from datetime import datetime, timezone
from tenacity import retry, stop_after_attempt, wait_exponential
from cities import CITIES

logging.basicConfig(level = logging.INFO, format = "%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

BASE_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"

PARAMS = {
    "hourly": "pm2_5,uv_index,carbon_monoxide",
    "past_days": 7,
    "forecast_days": 1,
    "timezone": "Asia/Kolkata"
}

@retry(stop = stop_after_attempt(3), wait = wait_exponential(min=2, max=10), reraise = True)
def fetch_air_quality_for_city(city:dict) -> pd.DataFrame:
    logger.info(f"Fetching air quality for {city['name']}:")

    params = {**PARAMS, "latitude":city['lat'], "longitude":city['lon']}
    response = requests.get(BASE_URL, params=params, timeout=30)
    response.raise_for_status()

    data = response.json()
    hourly = data.get("hourly",{})

    if not hourly:
        logger.warning(f"No data returned for {city['name']}")
        return pd.DataFrame()
    
    df = pd.DataFrame({
        "city" : city['name']
        ,"country" : city['country']
        ,"latitude" : city['lat']
        ,"longitude" : city['lon']
        ,"recorded_at" : pd.to_datetime(hourly["time"], format= "%Y-%m-%dT%H:%M")
        ,"pm2_5" : hourly.get("pm2_5",[])
        , "uv_index": hourly.get("uv_index", [])
        ,"carbon_monoxide": hourly.get("carbon_monoxide", [])
    })

    logger.info(f"Fetched {len(df)} air quality rows for {city['name']}")
    return df


def extract_all_air_quality() -> pd.DataFrame:
    all_dfs = []
    for city in CITIES:
        try:
            df = fetch_air_quality_for_city(city)
            if not df.empty:
                all_dfs.append(df)
        except Exception as e:
            logger.error(f"Failed to fetch {city['name']}: {e}")

    if not all_dfs:
        logger.error("No air quality data available for any city.")
        return pd.DataFrame()
    
    combined = pd.concat(all_dfs,ignore_index=True)
    logger.info(f"Total Air quality rows fetched: {len(combined)}")
    return combined

if __name__ == "__main__":
    df = extract_all_air_quality()
    if not df.empty:
        print(df.head(10))
        print(f"\nShape: {df.shape}")
        print(f"Cities: {df['city'].unique()}")
        print(f"Date range: {df['recorded_at'].min()} to {df['recorded_at'].max()}")
        