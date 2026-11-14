import json

import pika


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
        queue=settings.transfers_queue,
        durable=True,
        arguments={
            "x-dead-letter-exchange": settings.transfers_dlx,
            "x-dead-letter-routing-key": settings.transfers_dlq_routing_key,
        },
    )


def publish(settings, message):
    credentials = pika.PlainCredentials(settings.rabbitmq_user, settings.rabbitmq_password)
    parameters = pika.ConnectionParameters(
        host=settings.rabbitmq_host, credentials=credentials, socket_timeout=3
    )
    connection = pika.BlockingConnection(parameters)
    try:
        channel = connection.channel()
        declare_topology(channel, settings)
        channel.basic_publish(
            exchange="",
            routing_key=settings.transfers_queue,
            body=json.dumps(message),
            properties=pika.BasicProperties(
                delivery_mode=2,
                headers={"x-retry-count": 0},
            ),
        )
    finally:
        connection.close()