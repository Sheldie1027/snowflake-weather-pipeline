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

EXAMPLE_BLOCK = """Below is an example showing the exact report STYLE expected. The cities and numbers here are FICTIONAL and must NEVER appear in your report — they only demonstrate formatting.

    EXAMPLE INPUT:
        - Riverton (2020-01-01): Avg 29.1C (max 31, min 27) | Humidity 78% | PM2.5 42.0 (Moderate) | UV 8.1
        - Hillcrest (2020-01-01): Avg 34.5C (max 38, min 31) | Humidity 45% | PM2.5 88.0 (Unhealthy) | UV 9.4

    EXAMPLE REPORT:
        Overall, conditions vary — Hillcrest is hot and polluted while Riverton stays humid but moderate.

        Riverton: Averaged 29.1C (27-31C) with high humidity at 78%. Air quality was Moderate (PM2.5 42.0); UV high at 8.1.

        Hillcrest: Hot at 34.5C (31-38C) with lower humidity of 45%. Air quality was Unhealthy (PM2.5 88.0); UV very high at 9.4.

    Now write a report in EXACTLY this style for the REAL data below."""

SYSTEM_PROMPT = """You are a meteorological data analyst writing a daily weather intelligence report. Reports typically cover Indian cities such as Mumbai, Bangalore, Delhi, and Chennai.

    Your rules:
        - Use ONLY the numbers and facts provided in the REAL DATA section. NEVER invent, estimate, or extrapolate any value. If a value is missing, write "Not available" for that value.
        - Report ONLY on cities that actually appear in the real data. Do NOT add, infer, or back-fill any city that is absent.
        - Any example shown is for FORMATTING ONLY. Its cities and numbers must never appear in your report.
        - Be concise and factual. No filler, no poetic language.
        - Report temperature in Celsius and reference air quality using the provided category (Good / Moderate / Unhealthy).
        - Do not give health or safety advice beyond what the air quality category implies.

    If the real data is empty, respond only with: "No data available."
    """

def generate_full_report() -> str:
    data_text = fetch_rich_summary()
    logger.info("Sending to Groq...")

    summary = call_groq(
        system_prompt=SYSTEM_PROMPT,
        user_message=f"{EXAMPLE_BLOCK}\n\nREAL DATA:\n\n{data_text}",
        temperature=0.2,
    )
    return summary


if __name__ == "__main__":
    report = generate_full_report()
    print("\n=== WEATHER INTELLIGENCE REPORT ===\n")
    print(report)

    with open("docs/ai_summary_output.txt", "w") as f:
        f.write(report)
    print("\nSaved to docs/ai_summary_output.txt")