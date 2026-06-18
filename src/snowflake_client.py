import os
import logging
from dotenv import load_dotenv
from cryptography.hazmat.primitives import serialization
import snowflake.connector
from snowflake.connector.pandas_tools import write_pandas

load_dotenv("config/.env")
logger = logging.getLogger(__name__)

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


def get_connection():
    conn = snowflake.connector.connect(
        user=os.getenv("SNOWFLAKE_USER"),
        #password=os.getenv("SNOWFLAKE_PASSWORD"),
        private_key=get_private_key(),
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE"),
        database=os.getenv("SNOWFLAKE_DATABASE"),
        schema=os.getenv("SNOWFLAKE_SCHEMA"),
        session_parameters={
            "QUERY_TAG": "weather-pipeline-python"
        }
    )
    logger.info("Snowflake connection established")
    return conn


def run_query(query: str, conn=None) -> list:
    close_after = False
    if conn is None:
        conn = get_connection()
        close_after = True

    cursor = conn.cursor()
    try:
        cursor.execute(query)
        results = cursor.fetchall()
        return results
    finally:
        cursor.close()
        if close_after:
            conn.close()


def run_query_df(query: str, conn=None):
    import pandas as pd
    close_after = False
    if conn is None:
        conn = get_connection()
        close_after = True

    cursor = conn.cursor()
    try:
        cursor.execute(query)
        df = cursor.fetch_pandas_all()
        return df
    finally:
        cursor.close()
        if close_after:
            conn.close()


def load_dataframe(df, table_name: str, database: str, schema: str, conn=None):
    close_after = False
    if conn is None:
        conn = get_connection()
        close_after = True

    try:
        success, nchunks, nrows, _ = write_pandas(
            conn=conn,
            df=df,
            table_name=table_name,
            database=database,
            schema=schema,
            auto_create_table=False,  # table must exist - you control the schema
            overwrite=False,
            use_logical_type=True
        )
        if success:
            logger.info(f"Loaded {nrows} rows into {database}.{schema}.{table_name}")
        else:
            logger.error(f"Failed to load data into {table_name}")
        return success, nrows
    finally:
        if close_after:
            conn.close()