import requests
import pandas as pd
import logging
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format = "%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

CITIES = [
    {"name": "Mumbai",    "country": "India", "lat": 19.07, "lon": 72.88},
    {"name": "Bangalore", "country": "India", "lat": 12.97, "lon": 77.59},
    {"name": "Delhi",     "country": "India", "lat": 28.70, "lon": 77.10},
]

BASE_URL = "https://api.open-meteo.com/v1/forecast"

PARAMS = {
    "hourly": "temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code",
    "past_days": 30,
    "forecast_days": 1,
    "timezone": "Asia/Kolkata"
}


def fetch_weather_for_city (city: dict) -> pd.DataFrame:
    logger.info(f"Fetching weather data for {city['name']}...")

    params = {
        **PARAMS,
        "latitude": city['lat'],
        "longitude": city['lon']
    }

    try:
        response = requests.get(BASE_URL, params=params , timeout = 30)
        response.raise_for_status()

    except requests.exceptions.Timeout:
        logger.error(f"Request timed out for {city['name']}")
        return pd.DataFrame()
    
    except requests.exceptions.HTTPError as e:
        logger.error(f"HTTP error for {city['name']}: {e}")
        return pd.DataFrame()
    
    except requests.exceptions.RequestException as e:
        logger.error(f"Request failed for {city['name']}: {e}")
        return pd.DataFrame()
    
    data = response.json()
    hourly = data.get("hourly",{})

    if not hourly:
        logger.warning(f"No hourly data available for {city['name']}")
        return pd.DataFrame()
    
    df = pd.DataFrame({
        "city": city["name"]
        ,"country": city["country"]
        ,"latitude": city["lat"]
        ,"longitude": city["lon"]
        ,"recorded_at": pd.to_datetime(hourly["time"], format="%Y-%m-%dT%H:%M")
        ,"temperature_c": hourly["temperature_2m"]
        ,"humidity_pct": hourly["relative_humidity_2m"]
        ,"windspeed_kmh": hourly["wind_speed_10m"]
        ,"weather_code": hourly["weather_code"]
        ,
    })

    logger.info(f"Fetched {len(df)} rows for {city['name']}")
    return df


def extract_all_cities() -> pd.DataFrame:

    all_dfs = []

    for city in CITIES:
        df = fetch_weather_for_city(city)
        if not df.empty:
            all_dfs.append(df)
        
    if not all_dfs:
        logger.error("No data fetched for any city.")
        return pd.DataFrame()
    
    combined = pd.concat(all_dfs, ignore_index= True)
    logger.info(f"Total rows extracted {len(combined)}")
    return combined

if __name__ == "__main__":
    df = extract_all_cities()
    if not df.empty:
        print(df.head(10))
        print(f"\nShape: {df.shape}")
        print(f"\nData range: {df['recorded_at'].min()} to {df['recorded_at'].max()}")