#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

ENV="${ENV:-stage}"
if [ -z "${API_PORT:-}" ] && [ -f "deploy/env/$ENV.env" ]; then
  # shellcheck disable=SC1090
  API_PORT="$(grep -E '^API_PORT=' "deploy/env/$ENV.env" | head -n1 | cut -d= -f2- | tr -d '\r' || true)"
fi
API_PORT="${API_PORT:-8080}"
BASE="http://127.0.0.1:${API_PORT}"
TIMEOUT="${SMOKE_TIMEOUT:-10}"
RETRIES="${SMOKE_RETRIES:-3}"

echo "smoke: base=$BASE (ENV=$ENV)"

curl_t() {
  curl -fsS --connect-timeout 3 --max-time "$TIMEOUT" "$@"
}

for i in $(seq 1 "$RETRIES"); do
  if curl_t "${BASE}/health" >/dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq "$RETRIES" ]; then
    echo "smoke FAILED: /health not ready after ${RETRIES} tries" >&2
    exit 1
  fi
  sleep 2
done

RESP=$(curl_t -X POST "${BASE}/transfers" \
  -H 'Content-Type: application/json' \
  -d '{"amount":"100.00","currency":"RUB","recipient":"TH1234567890"}')
ID=$(printf '%s' "$RESP" | python -c 'import json,sys; print(json.load(sys.stdin)["id"])')

curl_t "${BASE}/transfers/${ID}" >/dev/null

echo "smoke OK: transfer ${ID}"