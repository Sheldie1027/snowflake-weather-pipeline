import json
import re
import logging
import time
import os
from datetime import datetime, timezone
from snowflake_client import run_query_df
from llm_provider import get_provider

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXAMPLE_BLOCK = """Below is an example showing the exact report STYLE expected. The cities and numbers here are FICTIONAL and must NEVER appear in your report — they only demonstrate formatting.

    EXAMPLE INPUT:
        - Riverton (2020-01-01): Avg 29.1C (max 31, min 27) | Humidity 78% | PM2.5 42.0 (Moderate) | UV 8.1
        - Hillcrest (2020-01-01): Avg 34.5C (max 38, min 31) | Humidity 45% | PM2.5 88.0 (Unhealthy) | UV 9.4

    EXAMPLE REPORT:
        Overall, conditions vary — Hillcrest is hot and polluted while Riverton stays humid but moderate.

        Riverton: Averaged 29.1C (27-31C) with high humidity at 78%. Air quality was Moderate (PM2.5 42.0); UV high at 8.1.

        Hillcrest: Hot at 34.5C (31-38C) with lower humidity of 45%. Air quality was Unhealthy (PM2.5 88.0); UV very high at 9.4.

    Now write a report in EXACTLY this style for the REAL data below."""

SYSTEM_PROMPT = """You are a meteorological data analyst writing a daily weather intelligence report. Reports typically cover Indian cities such as Mumbai, Bangalore and Delhi.

    Your rules:
        - Use ONLY the numbers and facts provided in the REAL DATA section. NEVER invent, estimate, or extrapolate any value. If a value is missing, write "Not available" for that value.
        - Report ONLY on cities that actually appear in the REAL DATA section. Do NOT add, infer, or back-fill any city that is absent.
        - Any example shown is for FORMATTING ONLY. Its cities and numbers must never appear in your report.
        - Be concise and factual. No filler, no poetic language.
        - Report temperature in Celsius and reference air quality using the provided category (Good / Moderate / Unhealthy).
        - Do not give health or safety advice beyond what the air quality category implies.

    If the real data is empty, respond only with: "No data available."
    """

JSON_SYSTEM_PROMPT = """You are a meteorological data analyst. You output ONLY valid JSON — nothing else.

    Your rules:
        - Respond with a single valid JSON object and NOTHING else. No markdown fences, no preamble, no explanation, no trailing commentary.
        - Use ONLY the numbers and facts provided in the REAL DATA section. NEVER invent, estimate, or extrapolate any value.
        - Include ONLY cities that actually appear in the real data. Do NOT add or back-fill absent cities.
        - If a value is missing in the data, use null for numbers and "Not available" for air_quality.
        - Any example shown is for FORMATTING ONLY. Its cities and numbers must never appear in your output.

    The JSON object must have exactly this shape:
        {
            "overview": "one-sentence summary across all cities",
            "cities": [
                {
                    "city": "city name",
                    "avg_temp": 29.1,
                    "avg_pm25": 42.0,
                    "air_quality": "Good | Moderate | Unhealthy | Not available",
                    "comment": "one short factual sentence"
                }
            ],
            "alerts": ["short string for any notable condition, e.g. unhealthy air"]
        }
"""

JSON_EXAMPLE_BLOCK = """Below is an example showing the exact JSON shape expected. The cities and numbers are FICTIONAL and must NEVER appear in your output.

    EXAMPLE INPUT:
        - Riverton (2020-01-01): Avg 29.1C (max 31, min 27) | Humidity 78% | PM2.5 42.0 (Moderate) | UV 8.1
        - Hillcrest (2020-01-01): Avg 34.5C (max 38, min 31) | Humidity 45% | PM2.5 88.0 (Unhealthy) | UV 9.4

    EXAMPLE OUTPUT:
        {"overview": "Conditions vary, with Hillcrest hot and polluted while Riverton stays humid but moderate.", "cities": [{"city": "Riverton", "avg_temp": 29.1, "air_quality": "Moderate", "avg_pm25": 42.0, "comment": "Humid at 78% with moderate air quality."}, {"city": "Hillcrest", "avg_temp": 34.5, "air_quality": "Unhealthy", "avg_pm25": 88.0, "comment": "Hot at 34.5C with unhealthy air quality."}], "alerts": ["Hillcrest air quality is Unhealthy (PM2.5 88.0)."]}

    Now produce JSON in EXACTLY this shape for the REAL data below. Output ONLY the JSON object.
"""

EXPECTED_KEYS = {"overview", "cities", "alerts"}

MAX_DATA_TOKENS = 2000

DBT_SCHEMA = os.getenv("DBT_SCHEMA", "DBT_PROD")

def estimate_tokens(text: str) -> int:
    return len(text) // 4

def fetch_rich_summary() -> str:
    query = f"""
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
        FROM WEATHER_DB.{DBT_SCHEMA}.MART_CITY_DAILY_SUMMARY
        QUALIFY row_number() OVER (PARTITION BY city_name ORDER BY reading_date DESC) = 1
        ORDER BY city_name
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
    result =  "\n".join(lines)
    
    est = estimate_tokens(result)
    if est > MAX_DATA_TOKENS:
        logger.warning(
            "Data block is large (~%d tokens); truncating to protect the context window.", est
        )
        keep = MAX_DATA_TOKENS * 4
        result = result[:keep]

    logger.info("Data block: %d chars (~%d tokens)", len(result), est)
    return result

def generate_full_report() -> str:
    data_text = fetch_rich_summary()
    return _call_with_observability(
        label="prose_report",
        system_prompt=SYSTEM_PROMPT,
        user_message=f"{EXAMPLE_BLOCK}\n\nREAL DATA:\n\n{data_text}",
        temperature=0,
    )

def generate_structured_report() -> str:
    data_text = fetch_rich_summary()
    return _call_with_observability(
        label="structured_report",
        system_prompt=JSON_SYSTEM_PROMPT, 
        user_message=f"{JSON_EXAMPLE_BLOCK}\n\nREAL DATA:\n\n{data_text}",
        temperature=0,
    )

def _strip_json_fences(text: str) -> str:
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*", "", text)
    text = re.sub(r"\s*```$", "", text)

    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        text = text[start:end + 1]

    return text.strip()

def parse_structured_report(raw: str) -> dict:
    cleaned = _strip_json_fences(raw)

    try:
        data = json.loads(cleaned)
    except json.JSONDecodeError as e:
        logger.error("Failed to parse LLM JSON response: %s", e)
        logger.debug("Raw response was: %s", raw)
        return {
            "overview": "Report unavailable - the AI response could not be parsed.",
            "cities": [],
            "alerts": [],
            "_parse_failed": True,
        }

    if not isinstance(data, dict):
        logger.error("LLM returned valid JSON but not an object: %s", type(data))
        return {
            "overview": "Report unavailable - unexpected response shape.",
            "cities": [],
            "alerts": [],
            "_parse_failed": True,
        }

    return data

def validate_structured_report(data: dict) -> tuple[bool, list[str]]:
    problems = []

    missing = EXPECTED_KEYS - data.keys()
    if missing:
        problems.append(f"Missing top-level keys: {sorted(missing)}")

    if not isinstance(data.get("cities"), list):
        problems.append("'cities' is not a list")
    else:
        for i, city in enumerate(data["cities"]):
            if not isinstance(city, dict):
                problems.append(f"cities[{i}] is not an object")
                continue
            for key in ("city", "avg_temp", "air_quality", "avg_pm25", "comment"):
                if key not in city:
                    problems.append(f"cities[{i}] missing '{key}'")

    if not isinstance(data.get("alerts"), list):
        problems.append("'alerts' is not a list")

    return (len(problems) == 0, problems)

def render_report(data: dict) -> str:
    lines = ["=== WEATHER INTELLIGENCE REPORT ===\n"]
    lines.append(data.get("overview", "No overview available."))
    lines.append("")

    for city in data.get("cities", []):
        temp = city.get("avg_temp")
        temp_str = f"{temp}C" if temp is not None else "Not available"
        pm25 = city.get("avg_pm25")
        pm_str = f"{pm25}" if pm25 is not None else "Not available"
        lines.append(
            f"{city.get('city', 'Unknown')}: "
            f"Avg {temp_str} | PM2.5 {pm_str} | Air quality: {city.get('air_quality', 'Not available')}"
        )
        lines.append(f"  {city.get('comment', '')}")
        lines.append("")

    alerts = data.get("alerts", [])
    if alerts:
        lines.append("ALERTS:")
        for a in alerts:
            lines.append(f"  ! {a}")

    return "\n".join(lines)

def _call_with_observability(label: str, system_prompt: str, user_message: str, temperature: float) -> str:
    provider = get_provider()
    est_in = estimate_tokens(system_prompt + user_message)
    start = time.monotonic()

    try:
        out = provider.generate(
            system_prompt=system_prompt,
            user_message=user_message,
            temperature=temperature,
        )
    except Exception as e:
        elapsed = time.monotonic() - start
        logger.error(
            "LLM call FAILED | provider=%s | label=%s | est_input_tokens=%d | elapsed=%.2fs | error=%s: %s",
            provider.name, label, est_in, elapsed, type(e).__name__, e,
        )
        raise

    elapsed = time.monotonic() - start
    logger.info(
        "LLM call OK | provider=%s | label=%s | est_input_tokens=%d | output_chars=%d | elapsed=%.2fs",
        provider.name, label, est_in, len(out), elapsed,
    )

    if not out or not out.strip():
        logger.warning("LLM returned an empty response | provider=%s label=%s", provider.name, label)

    return out

if __name__ == "__main__":

    report = generate_full_report()
    print("\n=== PROSE REPORT ===\n")
    print(report)
    print("\n\n")
    with open("docs/ai_summary_output.txt", "w") as f:
        f.write(report)

    raw = generate_structured_report()
    data = parse_structured_report(raw)
    is_valid, problems = validate_structured_report(data)

    if not is_valid:
        logger.warning("Structured report validation problems: %s", problems)

    print("\n" + render_report(data))

    with open("docs/ai_summary_structured.json", "w") as f:
        json.dump(data, f, indent=2)

    print("\nSaved prose to docs/ai_summary_output.txt")
    print("Saved structured JSON to docs/ai_summary_structured.json")