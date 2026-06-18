import logging
from snowflake_client import run_query_df
from groq_client import call_groq

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)


def fetch_summary_data() -> str:
    query = """
        SELECT
            city,
            COUNT(*)                            AS total_readings,
            ROUND(AVG(temperature_c), 2)        AS avg_temp,
            MAX(temperature_c)                  AS max_temp,
            MIN(temperature_c)                  AS min_temp,
            ROUND(AVG(humidity_pct), 2)         AS avg_humidity,
            ROUND(AVG(windspeed_kmh), 2)        AS avg_windspeed,
            MIN(recorded_at)                    AS data_from,
            MAX(recorded_at)                    AS data_to
        FROM WEATHER_DB.RAW.RAW_WEATHER_API
        WHERE temperature_c IS NOT NULL
        GROUP BY city
        ORDER BY avg_temp DESC
    """

    df = run_query_df(query)

    if df.empty:
        return "No data available."

    lines = []
    for _, row in df.iterrows():
        lines.append(
            f"City: {row['CITY']} | "
            f"Readings: {row['TOTAL_READINGS']} | "
            f"Avg Temp: {row['AVG_TEMP']}°C | "
            f"Max: {row['MAX_TEMP']}°C | "
            f"Min: {row['MIN_TEMP']}°C | "
            f"Avg Humidity: {row['AVG_HUMIDITY']}% | "
            f"Avg Wind: {row['AVG_WINDSPEED']} km/h"
        )

    date_range = f"\nDate range: {df['DATA_FROM'].min()} to {df['DATA_TO'].max()}"
    return "\n".join(lines) + date_range


def generate_weather_summary() -> str:
    logger.info("Fetching summary data from Snowflake...")
    data_text = fetch_summary_data()

    logger.info("Sending to Groq for AI summary...")
    summary = call_groq(
        system_prompt="""You are a weather data analyst assistant. 
        When given weather statistics for multiple Indian cities, provide:
        1. A 2-3 sentence overview of conditions across each city
        2. Notable observations (hottest city, coolest city, most humid,chance of precipitation)
        3. Any anomalies or patterns worth flagging
        4. A one-line practical takeaway
        Keep the total response under 200 words. Be specific with numbers.""",
        user_message=f"Analyse this weather data from my pipeline:\n\n{data_text}",
        temperature=0.2
    )

    return summary


if __name__ == "__main__":
    summary = generate_weather_summary()
    print("\n=== AI WEATHER SUMMARY ===")
    print(summary)


    with open("docs/ai_summary_output.txt", "w") as f:
        f.write(summary)
    print("\nSummary saved to docs/ai_summary_output.txt")


    