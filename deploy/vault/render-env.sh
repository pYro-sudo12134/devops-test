#!/usr/bin/env bash
set -euo pipefail
ENV="${1:?usage: render-env.sh <env>}"
cd "$(dirname "$0")/.."

get() {
  docker compose exec -T vault vault kv get -field="$1" "secret/payment-stack/$ENV"
}

umask 077
cat > runtime.env <<EOT
DB_PASSWORD=$(get db_password)
RABBITMQ_PASSWORD=$(get rabbitmq_password)
PROVIDER_API_KEY=$(get provider_api_key)
GRAFANA_ADMIN_PASSWORD=$(get grafana_admin_password)
EOT
chmod 600 runtime.env