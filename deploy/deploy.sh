#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-stage}"
case "$ENV" in
  stage|prod) ;;
  *) echo "usage: deploy.sh <stage|prod>" >&2; exit 2 ;;
esac

SECRETS_SOURCE="${SECRETS_SOURCE:-vault}"
case "$SECRETS_SOURCE" in
  vault|env) ;;
  *) echo "SECRETS_SOURCE must be 'vault' or 'env'" >&2; exit 2 ;;
esac

cd "$(dirname "$0")"
COMPOSE="docker compose -f docker-compose.yml"
if [ -n "${COMPOSE_EXTRA_FILE:-}" ]; then
  COMPOSE="$COMPOSE -f $COMPOSE_EXTRA_FILE"
fi

if [ -f .last_version ]; then
  PREV_VERSION="$(cat .last_version)"
  export PREV_VERSION
fi

set -a
# shellcheck disable=SC1090
. "env/$ENV.env"
set +a

APP_VERSION="${APP_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
export APP_VERSION

if [ "$SECRETS_SOURCE" = "vault" ]; then
  $COMPOSE up -d --wait vault
  ./vault/seed.sh "$ENV"
  ./vault/render-env.sh "$ENV"
else
  umask 077
  : "${DB_PASSWORD:?DB_PASSWORD is required}"
  : "${RABBITMQ_PASSWORD:?RABBITMQ_PASSWORD is required}"
  : "${PROVIDER_API_KEY:?PROVIDER_API_KEY is required}"
  cat > runtime.env <<EOT
DB_PASSWORD=${DB_PASSWORD}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
PROVIDER_API_KEY=${PROVIDER_API_KEY}
EOT
  chmod 600 runtime.env
fi

$COMPOSE build api worker mock-provider

$COMPOSE run --rm --no-deps migrate

$COMPOSE up -d --remove-orphans --wait

if ! ./../scripts/smoke.sh; then
  echo "smoke failed, rolling back to ${PREV_VERSION:-unknown}" >&2
  if [ -n "${PREV_VERSION:-}" ]; then
    ./rollback.sh "$PREV_VERSION" || true
  fi
  exit 1
fi

echo "$APP_VERSION" > .last_version

../scripts/status.sh