#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

API_PORT="${API_PORT:-8080}"
BASE="http://127.0.0.1:${API_PORT}"

curl -fsS "${BASE}/health" >/dev/null

RESP=$(curl -fsS -X POST "${BASE}/transfers" \
  -H 'Content-Type: application/json' \
  -d '{"amount":"100.00","currency":"RUB","recipient":"TH1234567890"}')
ID=$(printf '%s' "$RESP" | python -c 'import json,sys; print(json.load(sys.stdin)["id"])')

curl -fsS "${BASE}/transfers/${ID}" >/dev/null

echo "smoke OK: transfer ${ID}"