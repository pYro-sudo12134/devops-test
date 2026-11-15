# LIMITS

- Vault — dev-режим (данные в памяти), не persistent. Для прода — Vault с storage backend (вне рамок теста).
- DLQ / лимит повторов для worker — не реализовано (L3).
- `provider.py` использует `verify=False` — не исправлено (L3).
- `request_id` в логах api/worker — не реализовано (L3).
- RED/бизнес-метрики, алерты, мета-мониторинг, дашборд — L4.
- `reporting-ui` не подключён к деплою (L4).
- CI проверяет env-путь; vault-путь (локальный stage) — вручную (Vault dev в CI не поднимаем, `profiles: disabled`).
- Образы в GHCR публичные (тест); в проде — приватные + pull secret.
- Боевых секретов/деплоя нет: CI не деплоит, compose-smoke эфемерный.
- `restore.sh` не делает `--clean` по умолчанию (осознанно, чтобы не было разрушительных действий); чистое восстановление — отдельный шаг с подтверждением (RUNBOOK).
- `request_id`: mock-provider не логирует `X-Request-Id` (внешний сервис, не наш код). nginx перезаписывает клиентский `X-Request-Id` своим `$request_id` (без `map`); в проде — `map` (клиентский ID не теряется).
- `declare_topology` дублируется в api/worker (разные образы); общий модуль — при росте.
- **Dual-write** (api: `INSERT` + `publish` не атомарны) — риск зависшего PENDING при publish-fail. **Рекомендация:** transactional outbox + relay/CDC (Debezium) — в проде (не в тесте; изменение приложения, вне DevOps-зоны задания). Метрика `oldest_pending_age_seconds` + алерт + RUNBOOK ловят/разбирают.
- `oldest_pending_age_seconds` — на `on_message` (при простое worker «застывает»; если PENDING есть, а worker молчит — покажет старый возраст, это хорошо). В проде — по таймеру (и outbox/CDC для доставки).

- Alertmanager без интеграций (UI); в проде — slack/pagerduty/webhook.
- Grafana admin по умолчанию `admin` (тест); в проде — секрет/Vault.
- Prometheus скрейпит `api:8000` — одна реплика из 2 (Docker DNS); в проде — dns_sd/ServiceMonitor.
- DLQ-алерт — по `increase(worker_messages_total{result="dlq"}[5m])` (наша метрика); реальное состояние DLQ (`rabbitmq_queue_messages`) — опционально (rabbitmq job :15692).
- `oldest_pending_age_seconds` — на `on_message`; в проде — по таймеру (+ outbox/CDC).
- `b7f853ad` PENDING — артефакт 401→DLQ; для чистого дашборда — FAILED (или оставить как демо).

- Vault dev (root-токен, in-memory); в проде — persistent + AppRole/policies. Seed не перезаписывает существующий секрет — при смене набора/значений: `vault kv delete` + re-seed (RUNBOOK).
- Loki single-binary/filesystem/7d (тест); в проде — object storage/retention.
- `oldest_pending_age_seconds` — на `on_message` (при простое «застывает», показывает проблему); в проде — по таймеру (+outbox/CDC).