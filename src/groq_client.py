import os
import logging
from dotenv import load_dotenv
from groq import Groq


load_dotenv("config/.env")
logger = logging.getLogger(__name__)

client = Groq(api_key=os.getenv("GROQ_API_KEY"))
MODEL = os.getenv("GROQ_MODEL")


def call_groq(system_prompt: str, user_message: str, temperature: float = 0.5) -> str:
    try:
        response = client.chat.completions.create(
            model = MODEL,
            messages = [
                {"role": "system", "content":system_prompt},
                {"role": "user", "content": user_message}
            ],
            temperature= temperature,
            max_tokens=1000
        )
        return response.choices[0].message.content.strip()
    except Exception as e:
        logger.error(f"Find API call failed: {e}")
        return ""
    

if __name__ == "__main__":
    print("=== TEST 1: Basic call ===")
    response = call_groq(
        system_prompt="You are a helpful assistant. Answer concisely.",
        user_message="What is a data pipeline in one sentence?"
    )
    print(response)
    print()


    print("=== TEST 2: Weather data summarisation ===")
    sample_data = """
    City: Mumbai    | Avg Temp: 33.2°C | Max: 35.2°C | Min: 31.5°C | Avg Humidity: 74%
    City: Bangalore | Avg Temp: 25.1°C | Max: 27.5°C | Min: 23.8°C | Avg Humidity: 62%
    City: Delhi     | Avg Temp: 39.4°C | Max: 41.5°C | Min: 37.5°C | Avg Humidity: 41%
    Date range: 2026-06-11 to 2026-06-17
    """

    response = call_groq(
        system_prompt="""You are a weather data analyst. When given weather statistics,
        provide a concise 3-4 sentence summary covering: overall conditions,
        which city was hottest/coolest, any notable patterns or anomalies,
        and a one-line practical insight for someone planning travel.""",
        user_message=f"Summarise this weather data:\n{sample_data}",
        temperature=0.5
    )
    print(response)
