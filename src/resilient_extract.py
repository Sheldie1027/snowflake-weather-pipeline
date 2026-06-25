import requests
import logging
from datetime import datetime, timezone
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
    before_sleep_log,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)


# Custom exception for pipeline-specific errors
class APIExtractError(Exception):
    pass

class SnowflakeLoadError(Exception):
    pass


# Retry decorator: retry up to 3 times, wait 2s then 4s then 8s between attempts
@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception_type((requests.exceptions.RequestException, APIExtractError)),
    before_sleep=before_sleep_log(logger, logging.WARNING),
    reraise=True,  # if all retries fail, raise the original exception
)
def fetch_weather_with_retry(city: dict) -> dict:
    """
    Fetch weather data with automatic retry on failure.
    Retries up to 3 times with exponential backoff.
    """
    logger.info(f"Fetching data for {city['name']}...")

    response = requests.get(
        "https://api.open-meteo.com/v1/forecast",
        params={
            "latitude": city["lat"],
            "longitude": city["lon"],
            "hourly": "temperature_2m,relative_humidity_2m",
            "past_days": 1,
            "forecast_days": 1,
            "timezone": "Asia/Kolkata"
        },
        timeout=15
    )

    if response.status_code != 200:
        raise APIExtractError(
            f"API returned status {response.status_code} for {city['name']}"
        )

    data = response.json()
    hourly = data.get("hourly", {})

    if not hourly:
        raise APIExtractError(f"No hourly data returned for {city['name']}")

    logger.info(f"Successfully fetched {len(hourly['time'])} rows for {city['name']}")
    return {
        "city": city["name"],
        "rows": len(hourly["time"]),
        "fetched_at": datetime.now(timezone.utc).isoformat()
    }


def extract_all_with_resilience(cities: list) -> list:
    """
    Extract data for all cities.
    Failed cities are logged and skipped rather than crashing the whole pipeline.
    """
    results = []
    failed = []

    for city in cities:
        try:
            result = fetch_weather_with_retry(city)
            results.append(result)
        except Exception as e:
            logger.error(f"All retries failed for {city['name']}: {e}")
            failed.append({"city": city["name"], "error": str(e)})

    logger.info(f"Extraction complete: {len(results)} succeeded, {len(failed)} failed")

    if failed:
        logger.warning(f"Failed cities: {[f['city'] for f in failed]}")

    return results


if __name__ == "__main__":
    cities = [
        {"name": "Mumbai",    "lat": 19.07, "lon": 72.88},
        {"name": "Bangalore", "lat": 12.97, "lon": 77.59},
        {"name": "Delhi",     "lat": 28.70, "lon": 77.10},
    ]

    results = extract_all_with_resilience(cities)
    for r in results:
        print(f"{r['city']}: {r['rows']} rows fetched at {r['fetched_at']}")