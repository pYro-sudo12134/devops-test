#!/usr/bin/env bash
set -euo pipefail

NEW_KEY="${1:?usage: rotate-provider-key.sh <new-provider-api-key>}"
cd "$(dirname "$0")/.."

ENV_FILE="deploy/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "$ENV_FILE not found" >&2
  exit 1
fi

tmp="$(mktemp)"
awk -v k="$NEW_KEY" '
  BEGIN { done=0 }
  /^PROVIDER_API_KEY=/ { print "PROVIDER_API_KEY=" k; done=1; next }
  { print }
  END { if (!done) print "PROVIDER_API_KEY=" k }
' "$ENV_FILE" > "$tmp"
mv "$tmp" "$ENV_FILE"
chmod 600 "$ENV_FILE"
echo "updated $ENV_FILE (PROVIDER_API_KEY)"

cd deploy
if docker compose exec -T vault vault kv get "secret/payment-stack/stage" >/dev/null 2>&1; then
  docker compose exec -T vault vault kv patch "secret/payment-stack/stage" \
    provider_api_key="$NEW_KEY" >/dev/null
  echo "vault kv patch provider_api_key"
else
  bash ./vault/seed.sh stage
  echo "vault seed (initial)"
fi

bash ./vault/render-env.sh stage
echo "runtime.env re-rendered"

PROVIDER_API_KEY="$NEW_KEY" \
  docker compose up -d --force-recreate mock-provider worker

if ! bash ../scripts/smoke.sh; then
  echo "smoke failed after rotation; check logs worker/mock-provider" >&2
  exit 1
fi

echo "rotation OK: PROVIDER_API_KEY updated"