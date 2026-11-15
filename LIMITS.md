# LIMITS

## Инфраструктура
- Vault dev (in-memory, root-токен); прод — persistent + AppRole/policies, аудит.
- Alertmanager без интеграций (UI); прод — slack/pagerduty/webhook.
- Prometheus скрейпит `api:8000` — одна реплика из 2 (Docker DNS); прод — dns_sd/ServiceMonitor.
- TLS: клиент→nginx — HTTP (прод TLS-терминация); внутри сети plain (прод mTLS/mesh). TLS к mock-provider — проверяется.
- GHCR-пакеты публичные (тест); прод — приватные + pull secret.
- `mock-provider` self-signed + `/admin/fail-mode` без auth (тестовая фича).
- Grafana admin — initial из Vault; смена — `grafana cli` (прод — SSO/oauth).
- Loki single-binary/filesystem/7d (тест); прод — object storage/retention.
- `management_metrics_collection` deprecated (warning, безвреден); прод — обновить RabbitMQ/отключить.

## Приложение / надёжность
- **Dual-write** (INSERT+publish) не атомарен; **outbox/CDC** — рекомендация (прод), не реализовано (вне DevOps-зоны; 3 суток). Метрика/алерт + RUNBOOK ловят.
- Retry — фиксированный TTL 10с (одна retry-очередь); прод — экспоненциальный backoff/несколько очередей.
- `oldest_pending_age_seconds` — на `on_message` (при простое «застывает»; показывает проблему); прод — по таймеру (+outbox/CDC).
- `declare_topology` дублируется в api/worker (разные образы); общий модуль — при росте.
- `request_id`: mock-provider не логирует `X-Request-Id` (внешний); nginx `map` (клиентский не теряется).
- `*_created` (prometheus_client) — авто-метка counter'а, не используется.
- `b7f853ad` PENDING — артефакт 401→DLQ; для чистого дашборда — FAILED (или оставить как демо).
- Ротация ключей: только `PROVIDER_API_KEY` (внешний). DB_PASSWORD/RABBITMQ_PASSWORD — не ротированы (rolling restart/даунтайм, риск); прод — `ALTER USER`/`change_password` + Vault KV v2 + двойные креды. `VAULT_DEV_ROOT_TOKEN` — dev. Ротация **логов** — json-file 10m×3 + Loki 7d.
- Vault seed не перезаписывает существующий секрет — при смене: `vault kv delete` + re-seed.
- `docker-compose.reporting.yml` — override; `make deploy` не поднимает наблюдаемость (по дизайну).
- `restore_check` — временная БД (`verify-restore`); при блокировках — `DROP ... WITH (FORCE)`.
- Порты: `vault:8200`, `rabbitmq:15672`, `prometheus:9090`, `alertmanager:9093`, `grafana` (через reporting-ui:8090), `loki:3100`, `alloy:12345` — `127.0.0.1` (localhost). `reverse-proxy` (api) — `0.0.0.0:${API_PORT}` (клиентский; тест — localhost; прод — за LB/TLS, не `0.0.0.0` напрямую).
- Клиент→nginx — HTTP (TLS не ставили: тест, localhost; прод — TLS-терминация на nginx/Let's Encrypt). TLS к mock-provider — проверяется (`PROVIDER_CA_BUNDLE`) — единственный TLS-канал.