import os
from dataclasses import dataclass


def required(name):
    value = os.environ.get(name, "")
    if not value:
        raise SystemExit(f"{name} is not set")
    return value


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_name: str
    db_user: str
    db_password: str
    rabbitmq_host: str
    rabbitmq_user: str
    rabbitmq_password: str
    provider_api_key: str
    log_level: str
    app_version: str
    transfers_queue: str
    transfers_dlq: str
    transfers_dlx: str
    transfers_dlq_routing_key: str
    worker_max_retries: int

    @property
    def dsn(self):
        return f"host={self.db_host} dbname={self.db_name} user={self.db_user} password={self.db_password} connect_timeout=3"


def load_settings():
    return Settings(
        db_host=os.environ.get("DB_HOST", "db"),
        db_name=os.environ.get("POSTGRES_DB", "payments"),
        db_user=os.environ.get("POSTGRES_USER", "payments"),
        db_password=required("DB_PASSWORD"),
        rabbitmq_host=os.environ.get("RABBITMQ_HOST", "rabbitmq"),
        rabbitmq_user=os.environ.get("RABBITMQ_DEFAULT_USER", "payments"),
        rabbitmq_password=required("RABBITMQ_PASSWORD"),
        provider_api_key=required("PROVIDER_API_KEY"),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
        app_version=os.environ.get("APP_VERSION", "dev"),
        transfers_queue=os.environ.get("TRANSFERS_QUEUE", "transfers"),
        transfers_dlq=os.environ.get("TRANSFERS_DLQ", "transfers.dlq"),
        transfers_dlx=os.environ.get("TRANSFERS_DLX", "transfers.dlx"),
        transfers_dlq_routing_key=os.environ.get("TRANSFERS_DLQ_ROUTING_KEY", "transfers.dlq"),
        worker_max_retries=int(os.environ.get("WORKER_MAX_RETRIES", "3")),
    )