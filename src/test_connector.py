import logging
from snowflake_client import get_connection, run_query, run_query_df

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

def main():
    conn = get_connection()

    # Test 1: basic query
    print("\n=== TEST 1: Basic query ===")
    results = run_query("SELECT CURRENT_USER(), CURRENT_DATABASE(), CURRENT_SCHEMA()", conn)
    print(f"User: {results[0][0]}, DB: {results[0][1]}, Schema: {results[0][2]}")

    # Test 2: count rows in your table
    print("\n=== TEST 2: Row count ===")
    results = run_query("SELECT COUNT(*) AS cnt FROM RAW_WEATHER_API", conn)
    print(f"Rows in RAW_WEATHER_LOAD: {results[0][0]}")

    # Test 3: fetch as DataFrame
    print("\n=== TEST 3: Fetch as DataFrame ===")
    df = run_query_df("SELECT city, AVG(temperature_c) as avg_temp FROM RAW_WEATHER_API GROUP BY city", conn)
    print(df)

    conn.close()
    print("\nAll tests passed.")

if __name__ == "__main__":
    main()