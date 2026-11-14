import logging

import requests

log = logging.getLogger("worker.provider")


def send_payout(settings, transfer_id, amount, currency, recipient, request_id=None):
    headers = {
        "X-Api-Key": settings.provider_api_key,
        "Idempotency-Key": str(transfer_id),
    }
    if request_id:
        headers["X-Request-Id"] = request_id

    log.info(
        "payout request transfer=%s amount=%s %s request_id=%s",
        transfer_id, amount, currency, request_id,
    )

    response = requests.post(
        f"{settings.provider_url}/payouts",
        json={"reference": str(transfer_id), "amount": str(amount), "currency": currency, "recipient": recipient},
        headers=headers,
        timeout=10,
        verify=settings.provider_ca_bundle,
    )
    response.raise_for_status()
    return response.json()