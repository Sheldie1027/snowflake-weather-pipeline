FROM apache/airflow:2.9.1

# Create an isolated virtualenv for dbt so its dependencies
# never conflict with Airflow's Python environment.
RUN python -m venv /opt/airflow/dbt_venv && \
    /opt/airflow/dbt_venv/bin/pip install --no-cache-dir dbt-snowflake

# Everything else (Airflow providers, pipeline packages) stays in
# Airflow's own environment via _PIP_ADDITIONAL_REQUIREMENTS.