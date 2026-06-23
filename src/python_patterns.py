import time
import logging
from datetime import datetime, timezone

# Example 1: a simple timing decorator
def timer(func):
    def wrapper(*args, **kwargs):
        start = datetime.now(timezone.utc)
        result = func(*args, **kwargs)
        end = datetime.now(timezone.utc)
        print(f"{func.__name__} took {(end - start).total_seconds():.3f} seconds")
        return result
    return wrapper

@timer
def fetch_data():
    time.sleep(0.5)  # simulate API call
    return "data fetched"

result = fetch_data()
# Prints: fetch_data took 0.500 seconds
print(result)

# Example 2: Context manager for DB connections
class SnowflakeContext:
    def __enter__(self):
        print("Opening Snowflake connection")
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        print("Closing Snowflake connection")
        if exc_type:
            print(f"Error occurred: {exc_val}")
        return False  # don't suppress exceptions

with SnowflakeContext() as ctx:
    print("Running query inside context")
    # connection auto-closes when block exits
    # even if an error occurs

# Example 3: timezone-aware datetime (never use utcnow())
now_correct = datetime.now(timezone.utc)
print(f"Correct: {now_correct}")

# This is what you use in ALL pipeline code going forward

# Proper logging setup - use this in all pipeline scripts
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
    handlers=[
        logging.StreamHandler(),                    # prints to console
        logging.FileHandler("docs/pipeline.log")    # writes to file
    ]
)
logger = logging.getLogger(__name__)

logger.info("Pipeline started")
logger.warning("This is a warning")
logger.error("This is an error - won't crash the program")

try:
    x = 1 / 0
except ZeroDivisionError as e:
    logger.exception(f"Caught an exception: {e}")
    # logger.exception also prints the full traceback