import logging
import os
from airflow.utils.email import send_email
from dbt_results import summarise_dbt_failures

logger = logging.getLogger(__name__)

ALERT_EMAIL = os.getenv("ALERT_EMAIL")

def build_failure_message(context) -> str:
    ti = context.get("task_instance")
    exception = context.get("exception")

    return (
        f"PIPELINE FAILURE\n"
        f"DAG:       {ti.dag_id}\n"
        f"Task:      {ti.task_id}\n"
        f"Run:       {context.get('run_id')}\n"
        f"Try:       {ti.try_number} of {ti.max_tries + 1}\n"
        f"Error:     {type(exception).__name__ if exception else 'unknown'}: {exception}\n"
        f"Log URL:   {ti.log_url}\n"
    )


def alert_on_failure(context) -> None:
    message = build_failure_message(context)
    logger.error(message)

    ti = context.get("task_instance")
    subject = f"[Airflow] FAILED: {ti.dag_id}.{ti.task_id}"

    try:
        send_email(
            to=[ALERT_EMAIL],
            subject=subject,
            html_content=f"<pre>{message}</pre>",
        )
        logger.info("Failure alert email sent to %s", ALERT_EMAIL)
    except Exception as e:
        # An alert failing must never mask the original failure
        logger.error("Failed to send alert email: %s", e)


def alert_on_dbt_failure(context) -> None:
    message = build_failure_message(context)

    dbt_detail = summarise_dbt_failures()
    if dbt_detail:
        message += f"\n\nDATA QUALITY DETAIL:\n{dbt_detail}"

    logger.error(message)

    ti = context.get("task_instance")
    subject = f"[Airflow] FAILED: {ti.dag_id}.{ti.task_id}"

    try:
        send_email(
            to=[ALERT_EMAIL],
            subject=subject,
            html_content=f"<pre>{message}</pre>",
        )
        logger.info("dbt failure alert email sent")
    except Exception as e:
        logger.error("Failed to send dbt alert email: %s", e)