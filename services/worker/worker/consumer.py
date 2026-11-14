import logging

import pika
import psycopg
from prometheus_client import Counter, Gauge, start_http_server

from .config import load_settings
from .messages import parse_message
from .provider import send_payout

log = logging.getLogger("worker")

MESSAGES = Counter("worker_messages_total", "Processed messages", ["result"])
TRANSFERS = Counter("transfers_total", "Transfers by final status", ["status"])
OLDEST_PENDING = Gauge("oldest_pending_age_seconds", "Age of the oldest PENDING transfer (seconds)")


def declare_topology(channel, settings):
    channel.exchange_declare(
        exchange=settings.transfers_dlx, exchange_type="direct", durable=True
    )
    channel.queue_declare(queue=settings.transfers_dlq, durable=True)
    channel.queue_bind(
        queue=settings.transfers_dlq,
        exchange=settings.transfers_dlx,
        routing_key=settings.transfers_dlq_routing_key,
    )
    channel.queue_declare(
        queue=settings.transfers_retry_queue,
        durable=True,
        arguments={
            "x-message-ttl": settings.transfers_retry_ttl_ms,
            "x-dead-letter-exchange": "",
            "x-dead-letter-routing-key": settings.transfers_queue,
        },
    )
    channel.queue_declare(
        queue=settings.transfers_queue,
        durable=True,
        arguments={
            "x-dead-letter-exchange": settings.transfers_dlx,
            "x-dead-letter-routing-key": settings.transfers_dlq_routing_key,
        },
    )


def process(settings, body, request_id=None):
    transfer_id = parse_message(body)
    with psycopg.connect(settings.dsn) as conn:
        row = conn.execute(
            "SELECT amount_minor, currency, recipient, status FROM transfers WHERE id = %s FOR UPDATE",
            (transfer_id,),
        ).fetchone()
        if row is None:
            raise LookupError(f"transfer {transfer_id} does not exist")
        amount_minor, currency, recipient, status = row
        if status != "PENDING":
            return
        payout = send_payout(
            settings, transfer_id, f"{amount_minor / 100:.2f}", currency, recipient,
            request_id=request_id,
        )
        conn.execute(
            "UPDATE transfers SET status = %s, provider_reference = %s, updated_at = now() WHERE id = %s",
            (payout["status"], payout["payout_id"], transfer_id),
        )
    TRANSFERS.labels(payout["status"]).inc()
    log.info("transfer %s is %s request_id=%s", transfer_id, payout["status"], request_id)


def update_oldest_pending(settings):
    """Бизнес-метрика: возраст самого старого PENDING (секунды)."""
    try:
        with psycopg.connect(settings.dsn) as conn:
            row = conn.execute(
                "SELECT EXTRACT(EPOCH FROM (now() - min(created_at))) FROM transfers WHERE status = 'PENDING'"
            ).fetchone()
        OLDEST_PENDING.set(float(row[0]) if row and row[0] is not None else 0.0)
    except Exception as exc:
        log.warning("update_oldest_pending failed: %s", exc)


def _retry_count(properties) -> int:
    headers = (properties.headers or {}) if properties else {}
    try:
        return int(headers.get("x-retry-count", 0))
    except (TypeError, ValueError):
        return 0


def _request_id(properties):
    headers = (properties.headers or {}) if properties else {}
    return headers.get("x-request-id")


def _safe_transfer_id(body):
    try:
        return str(parse_message(body))
    except Exception:
        return "?"


def main():
    settings = load_settings()
    logging.basicConfig(
        level=settings.log_level, format="%(asctime)s %(levelname)s %(name)s %(message)s"
    )
    logging.getLogger("pika").setLevel(logging.WARNING)

    start_http_server(8001)
    credentials = pika.PlainCredentials(settings.rabbitmq_user, settings.rabbitmq_password)
    connection = pika.BlockingConnection(
        pika.ConnectionParameters(host=settings.rabbitmq_host, credentials=credentials)
    )
    channel = connection.channel()
    declare_topology(channel, settings)
    channel.basic_qos(prefetch_count=1)

    def on_message(ch, method, properties, body):
        request_id = _request_id(properties)
        retries = _retry_count(properties)
        try:
            process(settings, body, request_id=request_id)
        except Exception as exc:
            retries += 1
            if retries >= settings.worker_max_retries:
                log.error(
                    "message moved to DLQ after %d retries: %s (transfer=%s request_id=%s)",
                    retries, exc, _safe_transfer_id(body), request_id,
                )
                MESSAGES.labels("dlq").inc()
                ch.basic_nack(method.delivery_tag, requeue=False)
                update_oldest_pending(settings)
                return
            log.warning(
                "retry %d/%d via %s (ttl=%sms): %s (transfer=%s request_id=%s)",
                retries, settings.worker_max_retries,
                settings.transfers_retry_queue, settings.transfers_retry_ttl_ms,
                exc, _safe_transfer_id(body), request_id,
            )
            MESSAGES.labels("retried").inc()
            headers = {"x-retry-count": retries}
            if request_id:
                headers["x-request-id"] = request_id
            ch.basic_publish(
                exchange="",
                routing_key=settings.transfers_retry_queue,
                body=body,
                properties=pika.BasicProperties(delivery_mode=2, headers=headers),
            )
            ch.basic_ack(method.delivery_tag)
            update_oldest_pending(settings)
            return
        MESSAGES.labels("processed").inc()
        ch.basic_ack(method.delivery_tag)
        update_oldest_pending(settings)

    channel.basic_consume(queue=settings.transfers_queue, on_message_callback=on_message)
    log.info(
        "consuming %s (max_retries=%d, retry=%s ttl=%sms, dlq=%s)",
        settings.transfers_queue, settings.worker_max_retries,
        settings.transfers_retry_queue, settings.transfers_retry_ttl_ms,
        settings.transfers_dlq,
    )
    channel.start_consuming()


if __name__ == "__main__":
    main()