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

PULL_IMAGES="${PULL_IMAGES:-0}"

cd "$(dirname "$0")"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

COMPOSE="docker compose -f docker-compose.yml"
if [ -n "${COMPOSE_EXTRA_FILE:-}" ]; then
  COMPOSE="$COMPOSE -f $COMPOSE_EXTRA_FILE"
fi

if [ "$SECRETS_SOURCE" = "vault" ]; then
  : "${VAULT_DEV_ROOT_TOKEN:?VAULT_DEV_ROOT_TOKEN is required for SECRETS_SOURCE=vault}"
  export VAULT_DEV_ROOT_TOKEN
else
  : "${DB_PASSWORD:?DB_PASSWORD is required}"
  : "${RABBITMQ_PASSWORD:?RABBITMQ_PASSWORD is required}"
  : "${PROVIDER_API_KEY:?PROVIDER_API_KEY is required}"
fi

if [ -f .last_version ]; then
  PREV_VERSION="$(cat .last_version)"
  export PREV_VERSION
fi

set -a
# shellcheck disable=SC1090
. "env/$ENV.env"
set +a

APP_VERSION="${APP_VERSION:-$(git describe --tags --always --dirty 2>/dev/null || true)}"
if [ -z "$APP_VERSION" ]; then
  echo "APP_VERSION is required (git describe failed; set APP_VERSION env)" >&2
  exit 2
fi
export APP_VERSION

touch runtime.env
chmod 600 runtime.env

if [ "$SECRETS_SOURCE" = "vault" ]; then
  $COMPOSE up -d --wait vault
  bash ./vault/seed.sh "$ENV"
  bash ./vault/render-env.sh "$ENV"
else
  umask 077
  cat > runtime.env <<EOT
DB_PASSWORD=${DB_PASSWORD}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}
PROVIDER_API_KEY=${PROVIDER_API_KEY}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
EOT
  chmod 600 runtime.env
fi

require_runtime_secret() {
  local name="$1" val
  val="$(grep -E "^${name}=" runtime.env | head -n1 | cut -d= -f2- | tr -d '\r' || true)"
  if [ -z "${val}" ]; then
    echo "runtime.env: ${name} is empty/missing (check Vault seed / .env)" >&2
    exit 1
  fi
}
require_runtime_secret DB_PASSWORD
require_runtime_secret RABBITMQ_PASSWORD
require_runtime_secret PROVIDER_API_KEY
if [ -n "${COMPOSE_EXTRA_FILE:-}" ] && echo "$COMPOSE_EXTRA_FILE" | grep -q "reporting"; then
  require_runtime_secret GRAFANA_ADMIN_PASSWORD
  GRAFANA_ADMIN_PASSWORD="$(grep -E '^GRAFANA_ADMIN_PASSWORD=' runtime.env | head -n1 | cut -d= -f2- | tr -d '\r')"
  export GRAFANA_ADMIN_PASSWORD
fi

PROVIDER_API_KEY="$(grep -E '^PROVIDER_API_KEY=' runtime.env | head -n1 | cut -d= -f2- | tr -d '\r')"
export PROVIDER_API_KEY

if [ "$PULL_IMAGES" = "1" ]; then
  echo "pulling images (PULL_IMAGES=1)"
  $COMPOSE pull api worker mock-provider migrate
else
  echo "building images"
  $COMPOSE build api worker mock-provider migrate
fi

$COMPOSE up -d --wait db

$COMPOSE run --rm --no-deps -T migrate

$COMPOSE up -d --wait

if ! bash ../scripts/smoke.sh; then
  echo "smoke failed, rolling back to ${PREV_VERSION:-unknown}" >&2
  if [ -n "${PREV_VERSION:-}" ]; then
    bash ./rollback.sh "$PREV_VERSION" || true
  fi
  exit 1
fi

echo "$APP_VERSION" > .last_version
bash ../scripts/status.sh