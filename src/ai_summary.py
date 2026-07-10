import logging
from datetime import datetime, timezone
from snowflake_client import run_query_df
from groq_client import call_groq

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def fetch_rich_summary() -> str:
    
    """
    Pull the daily city summary from the dbt-built mart for AI analysis.
    """

    query = """
        SELECT
            city_name,
            reading_date,
            avg_temp,
            max_temp,
            min_temp,
            avg_humidity,
            avg_pm25,
            avg_uv,
            air_quality_category
        FROM WEATHER_DB.DBT_DEV.MART_CITY_DAILY_SUMMARY
        ORDER BY reading_date DESC, city_name
        LIMIT 40
    """

    df = run_query_df(query)
    if df.empty:
        return "No data available in the daily summary mart yet."

    lines = [f"Weather & Air Quality Daily Summary — generated {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M')} UTC\n"]
    for _, row in df.iterrows():
        lines.append(
            f"- {row['CITY_NAME']} ({row['READING_DATE']}): "
            f"Avg {row['AVG_TEMP']}C (max {row['MAX_TEMP']}, min {row['MIN_TEMP']}) | "
            f"Humidity {row['AVG_HUMIDITY']}% | "
            f"PM2.5 {row['AVG_PM25']} ({row['AIR_QUALITY_CATEGORY']}) | "
            f"UV {row['AVG_UV']}"
        )
    return "\n".join(lines)


def generate_full_report() -> str:
    data_text = fetch_rich_summary()
    logger.info("Sending to Groq...")

    summary = call_groq(
        system_prompt="""You are a senior weather data analyst. 
        Given statistics from a data pipeline covering multiple Indian cities:
        1. Write a professional 3-4 sentence executive summary of conditions of each city
        2. Identify which city had the most extreme conditions and why that matters
        3. Flag any patterns worth investigating (humidity, wind, temperature swings, feels like temperature vs recorded temperature)
        4. Give one actionable insight a city planner or traveller could use
        5. Relation of the current weather condition of these cities w.r.t climatic conditions observed every year
        Keep it under 350 words. Use specific numbers. Sound professional.""",
        user_message=f"Generate a weather intelligence report from this data:\n\n{data_text}",
        temperature=0.2
    )
    return summary


if __name__ == "__main__":
    report = generate_full_report()
    print("\n=== WEATHER INTELLIGENCE REPORT ===\n")
    print(report)

    with open("docs/ai_summary_output.txt", "w") as f:
        f.write(report)
    print("\nSaved to docs/ai_summary_output.txt")