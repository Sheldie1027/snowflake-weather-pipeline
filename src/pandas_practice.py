import pandas as pd
import numpy as np

df = pd.read_csv(r"C:\Users\sheld\OneDrive\Desktop\snowflake-weather-pipeline\docs\weather_sample.csv")

print("=== RAW DATAFRAME ===")
print(df)
print()

print("=== SHAPE (rows, columns) ===")
print(df.shape)
print()

print("=== COLUMN NAMES & DATA TYPES ===")
print(df.dtypes)
print()

print("=== FIRST 3 ROWS ===")
print(df.head(3))
print()

print("=== SUMMARY STATISTICS ===")
print(df.describe())
print()

print("=== ANY NULL VALUES? ===")
print(df.isnull().sum())
print()

df["recorded_at"] = pd.to_datetime(df["recorded_at"])

print("=== AFTER DATETIME FIX ===")
print(df.dtypes)
print()

df["date"] = df["recorded_at"].dt.date
df["hour"] = df["recorded_at"].dt.hour
df["day_of_week"] = df["recorded_at"].dt.day_name()
df["month"] = df["recorded_at"].dt.month
df["year"] = df["recorded_at"].dt.year

print("=== WITH DERIVED COLUMNS ===")
print(df[["city", "recorded_at", "date", "hour", "day_of_week"]].head(5))
print()

df = df.rename(columns={
    "city": "CITY",
    "country": "COUNTRY",
    "recorded_at": "RECORDED_AT",
    "temperature_c": "TEMPERATURE_C",
    "humidity_pct": "HUMIDITY_PCT",
    "windspeed_kmh": "WINDSPEED_KMH",
    "weather_code": "WEATHER_CODE"
})

print("=== RENAMED COLUMNS ===")
print(df.columns.tolist())
print()

df.columns = df.columns.str.lower()

hot_days = df[df["temperature_c"] > 35]
print("=== READINGS ABOVE 35°C ===")
print(hot_days[["city", "recorded_at", "temperature_c"]])
print()

city_summary = df.groupby("city").agg(
    avg_temp = ("temperature_c", "mean")
    ,max_temp = ("temperature_c", "max")
    ,min_temp = ("temperature_c", "min")
    ,avg_humidity = ("humidity_pct", "mean")
    ,row_count = ("temperature_c", "count")
).round(2).reset_index()

print("=== CITY SUMMARY ===")
print(city_summary)
print()

print("=== HOTTEST CITIES RANKED ===")
print(city_summary.sort_values("avg_temp", ascending=False))
print()


df_with_nulls = df.copy()
df_with_nulls.loc[2, "temperature_c"] = np.nan
df_with_nulls.loc[5, "humidity_pct"] = np.nan

print("=== NULL COUNT BEFORE CLEANING ===")
print(df_with_nulls.isnull().sum())


df_dropped = df_with_nulls.dropna()

print(f"\nRows before dropna: {len(df_with_nulls)}")
print(f"Rows after dropna:  {len(df_dropped)}")

city_meta = pd.DataFrame({
    "city": ["Mumbai", "Bangalore", "Delhi"],
    "state": ["Maharashtra", "Karnataka", "Delhi NCR"],
    "latitude": [19.07, 12.97, 28.70],
    "longitude": [72.88, 77.59, 77.10]
})

df_enriched = df.merge(city_meta, on="city", how="left")

print("=== ENRICHED DATAFRAME (with city metadata) ===")
print(df_enriched[["city", "state", "temperature_c", "latitude", "longitude"]].head(5))