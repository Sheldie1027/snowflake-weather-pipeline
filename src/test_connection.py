import os
from dotenv import load_dotenv
from cryptography.hazmat.primitives import serialization
import snowflake.connector

load_dotenv("config/.env")

def get_private_key():
    with open(os.getenv("SNOWFLAKE_PRIVATE_KEY_PATH"), "rb") as f:
        private_key = serialization.load_pem_private_key(
            f.read(),
            password=None
        )
    return private_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )

def test_snowflake_connection():
    conn = snowflake.connector.connect(
        user=os.getenv("SNOWFLAKE_USER"),
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        private_key=get_private_key(),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE"),
        database=os.getenv("SNOWFLAKE_DATABASE"),
        schema=os.getenv("SNOWFLAKE_SCHEMA"),
        role=os.getenv("SNOWFLAKE_ROLE"),
    )
    cursor = conn.cursor()
    cursor.execute("SELECT CURRENT_USER(), CURRENT_VERSION()")
    row = cursor.fetchone()
    print(f"Connected as: {row[0]}")
    print(f"Snowflake version: {row[1]}")
    cursor.close()
    conn.close()

if __name__ == "__main__":
    test_snowflake_connection()