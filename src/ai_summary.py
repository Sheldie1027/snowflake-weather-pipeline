import logging
from datetime import datetime, timezone
from snowflake_client import run_query_df
from groq_client import call_groq

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def fetch_rich_summary() -> str:

    query = """
        WITH daily_stats AS (
            SELECT
                c.city_name,
                c.state,
                d.full_date,
                d.day_of_week,
                w.category                          AS weather_category,
                ROUND(AVG(f.temperature_c), 2)      AS avg_temp,
                MAX(f.temperature_c)                AS max_temp,
                MIN(f.temperature_c)                AS min_temp,
                ROUND(AVG(f.humidity_pct), 2)       AS avg_humidity,
                ROUND(AVG(f.windspeed_kmh), 2)      AS avg_wind
            FROM WEATHER_DB.MARTS.FACT_WEATHER_READINGS f
            JOIN WEATHER_DB.MARTS.DIM_CITY c
                ON f.city_sk = c.city_sk AND c.is_current = TRUE
            JOIN WEATHER_DB.MARTS.DIM_DATE d
                ON f.date_sk = d.date_sk
            JOIN WEATHER_DB.MARTS.DIM_WEATHER_CODE w
                ON f.weather_code_sk = w.code_sk
            GROUP BY c.city_name, c.state, d.full_date, d.day_of_week, w.category
        ),
        city_summary AS (
            SELECT
                city_name,
                state,
                ROUND(AVG(avg_temp), 2)             AS overall_avg_temp,
                MAX(max_temp)                       AS overall_max_temp,
                MIN(min_temp)                       AS overall_min_temp,
                ROUND(AVG(avg_humidity), 2)         AS overall_avg_humidity,
                COUNT(DISTINCT full_date)           AS days_of_data,
                LISTAGG(DISTINCT weather_category, ', ')
                    WITHIN GROUP (ORDER BY weather_category) AS conditions_seen
            FROM daily_stats
            GROUP BY city_name, state
        )
        SELECT * FROM city_summary ORDER BY overall_avg_temp DESC
    """

    df = run_query_df(query)
    if df.empty:
        return "No data available in FACT tables yet."

    lines = [f"Weather Intelligence Report — Generated {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M')} UTC\n"]
    for _, row in df.iterrows():
        lines.append(
            f"• {row['CITY_NAME']} ({row['STATE']}): "
            f"Avg {row['OVERALL_AVG_TEMP']}°C | "
            f"Peak {row['OVERALL_MAX_TEMP']}°C | "
            f"Low {row['OVERALL_MIN_TEMP']}°C | "
            f"Humidity {row['OVERALL_AVG_HUMIDITY']}% | "
            f"Conditions: {row['CONDITIONS_SEEN']} | "
            f"{row['DAYS_OF_DATA']} days of data"
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
        3. Flag any patterns worth investigating (humidity, wind, temperature swings)
        4. Give one actionable insight a city planner or traveller could use
        5. Relation to the current weather condition of these cities in relation to climatic conditions
        Keep it under 250 words. Use specific numbers. Sound professional.""",
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