import logging
import uuid

import pika
import psycopg
from prometheus_client import CONTENT_TYPE_LATEST, Counter, generate_latest
from starlette.applications import Starlette
from starlette.responses import JSONResponse, Response
from starlette.routing import Route

from . import broker
from .config import load_settings
from .validation import InvalidTransfer, parse_transfer, to_minor

settings = load_settings()
logging.basicConfig(level=settings.log_level, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logging.getLogger("pika").setLevel(logging.WARNING)
log = logging.getLogger("api")
log.info("starting api version=%s log_level=%s", settings.app_version, settings.log_level)

REQUESTS = Counter("api_requests_total", "HTTP requests", ["method", "path", "status"])


def count(request, response):
    REQUESTS.labels(request.method, request.url.path.split("/")[1], response.status_code).inc()
    return response


def _request_id(request):
    return request.headers.get("X-Request-Id") or uuid.uuid4().hex


def _with_request_id(response, request_id):
    response.headers["X-Request-Id"] = request_id
    return response


async def health(request):
    try:
        with psycopg.connect(settings.dsn) as conn:
            conn.execute("SELECT 1")
    except Exception as exc:
        log.warning("health: db check failed: %s", exc)
        return JSONResponse({"status": "error", "db": "down"}, status_code=503)
    try:
        credentials = pika.PlainCredentials(settings.rabbitmq_user, settings.rabbitmq_password)
        params = pika.ConnectionParameters(
            host=settings.rabbitmq_host, credentials=credentials, socket_timeout=2,
        )
        conn = pika.BlockingConnection(params)
        conn.close()
    except Exception as exc:
        log.warning("health: rabbitmq check failed: %s", exc)
        return JSONResponse({"status": "error", "rabbitmq": "down"}, status_code=503)
    return JSONResponse({"status": "ok"})


def row_to_json(row):
    return {
        "id": str(row[0]),
        "amount": f"{row[1] / 100:.2f}",
        "currency": row[2],
        "recipient": row[3],
        "status": row[4],
        "provider_reference": row[5],
        "client_ip": row[6],
    }


SELECT = "SELECT id, amount_minor, currency, recipient, status, provider_reference, client_ip FROM transfers WHERE id = %s"


async def create_transfer(request):
    request_id = _request_id(request)
    try:
        amount, currency, recipient = parse_transfer(await request.json())
    except (InvalidTransfer, ValueError) as exc:
        log.warning("invalid transfer request_id=%s: %s", request_id, exc)
        return _with_request_id(count(request, JSONResponse({"error": str(exc)}, status_code=400)), request_id)
    transfer_id = uuid.uuid4()
    client_ip = request.client.host if request.client else None
    with psycopg.connect(settings.dsn) as conn:
        conn.execute(
            "INSERT INTO transfers (id, amount_minor, currency, recipient, status, client_ip) VALUES (%s, %s, %s, %s, %s, %s)",
            (transfer_id, to_minor(amount), currency, recipient, "PENDING", client_ip),
        )
        row = conn.execute(SELECT, (transfer_id,)).fetchone()
    broker.publish(settings, {"transfer_id": str(transfer_id)}, request_id=request_id)
    log.info("transfer created id=%s client_ip=%s request_id=%s", transfer_id, client_ip, request_id)
    return _with_request_id(count(request, JSONResponse(row_to_json(row), status_code=202)), request_id)


async def get_transfer(request):
    request_id = _request_id(request)
    try:
        transfer_id = uuid.UUID(request.path_params["transfer_id"])
    except ValueError:
        log.info("get transfer: invalid id request_id=%s", request_id)
        return _with_request_id(count(request, JSONResponse({"error": "not found"}, status_code=404)), request_id)
    with psycopg.connect(settings.dsn) as conn:
        row = conn.execute(SELECT, (transfer_id,)).fetchone()
    if row is None:
        log.info("get transfer id=%s not found request_id=%s", transfer_id, request_id)
        return _with_request_id(count(request, JSONResponse({"error": "not found"}, status_code=404)), request_id)
    log.info("get transfer id=%s status=%s request_id=%s", transfer_id, row[4], request_id)
    return _with_request_id(count(request, JSONResponse(row_to_json(row))), request_id)


async def metrics(request):
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


app = Starlette(
    routes=[
        Route("/health", health),
        Route("/metrics", metrics),
        Route("/transfers", create_transfer, methods=["POST"]),
        Route("/transfers/{transfer_id}", get_transfer),
    ]
)