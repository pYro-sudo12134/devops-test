# RUNBOOK

## Деплой
1. `cp deploy/.env.example deploy/.env` (заполнить).
2. `make deploy ENV=stage` / `make deploy-observability ENV=stage`.
3. `make status`, `make smoke`.

## Откат
- `./deploy/rollback.sh <version>` — api/worker на образ версии; `reverse-proxy` restart.
- **Схема БД НЕ откатывается** (forward-only; `003_add_amount_minor` — DROP COLUMN amount, необратим). Откат схемы — forward-fix (новая миграция).

## Секреты
- `.env` нет/пуст → `seed.sh`/`render-env.sh` падают (`:?`). Восстановить `.env`, `make deploy`.
- Vault: `vault kv get secret/payment-stack/stage`; если нет `grafana_admin_password` → `vault kv delete secret/payment-stack/stage` + re-seed.
- CI (`SECRETS_SOURCE=env`): нет `DB_PASSWORD`/`RABBITMQ_PASSWORD`/`PROVIDER_API_KEY` → `:?`.

## Grafana: не пускает / пароль
- `GF_SECURITY_ADMIN_PASSWORD` — **initial** (пустая БД/нет `grafana-data`); при существующем томе env игнорируется.
- Сброс: `docker compose ... exec grafana grafana cli admin reset-admin-password '<new>'`.
- Или (тест) `docker volume rm payment-stack_grafana-data` + `make deploy-observability` (admin пересоздастся; provisioning восстановится).

## Очередь растёт / DLQ
1. `docker compose exec rabbitmq rabbitmqctl list_queues name messages consumers`
   - `transfers` растёт, consumers=0 → worker упал.
   - `transfers.dlq > 0` → «ядовитые» после `WORKER_MAX_RETRIES` (3).
2. `logs worker | grep -iE "dlq|retry|moved"` — `message moved to DLQ ... transfer=<id> request_id=<...>`.
3. Разбор: transfer в БД, причина (битый JSON / нет transfer / 401/5xx).
4. Fix: replay из DLQ (UI 15672) после устранения; или FAILED.
5. Метрика: `rabbitmq_queue_messages_ready{queue="transfers.dlq"}` (per-queue); алерт `TransfersDLQNotEmpty`.

## Зависший PENDING (`oldest_pending_age_seconds > 300`)
1. `SELECT id, status, created_at FROM transfers WHERE status='PENDING' ORDER BY created_at;`
2. Причины: DLQ (ядовитое/401/5xx), publish fail (dual-write), потеря сообщения (volume `rabbitmq` пересоздавался), worker down, провайдер висит.
3. `rabbitmqctl list_queues`, `logs worker/api`.
4. Fix: replay из DLQ / FAILED / ручной retry; для publish-fail — outbox (прод) / ручной replay.
5. Пример: `b7f853ad` — 401 (mock без ключа) → DLQ → PENDING; fix mock → replay/FAILED.

## Отладка по request_id
- `X-Request-Id` (nginx `$request_id`/клиент) → api → очередь → worker → провайдер; возвращается в ответе api.
- `docker compose logs api worker | grep "<request_id>"`; Grafana → Explore → Loki: `{job="docker"} |= "<request_id>"`.
- TLS к mock-provider: `openssl x509 -in /certs/cert.pem -noout -text | grep DNS`.

## Ротация PROVIDER_API_KEY
1. `make rotate KEY=<new-key>` (`rotate-provider-key.sh`: `.env` → Vault `kv patch` → runtime.env → force-recreate mock/worker → smoke).
2. Окно: mock/worker разные ключи → 401 → retry (transfers.retry 10s) → DLQ при исчерпании. В проде — dual-key.
3. Откат: вернуть старый ключ (`.env`, Vault, render-env, force-recreate).

## Наблюдаемость
- Grafana: `http://127.0.0.1:8090` (reporting-ui), admin/`GRAFANA_ADMIN_PASSWORD`.
- Prometheus: `http://127.0.0.1:9090` (targets/alerts); Alertmanager: `http://127.0.0.1:9093`.
- Loki: Grafana Explore (`{service_name="payment-stack-api-1"}`), Alloy UI: `127.0.0.1:12345`.
- Алерты: `OldestPendingTooOld` (>300s), `TransfersDLQNotEmpty` (per-queue), `ApiDown`/`WorkerDown` (`up==0`), `NoTargetsUp` (absent).

## Бэкап / восстановление
- `make backup` (`pg_dump payments`, ротация 7, chmod 600).
- `make restore FILE=...` (без `--clean` по умолчанию).
- `make verify-restore` — бэкап → временная БД `restore_check` → сверка rows (`OK: N rows`).

## Логи
- `docker compose logs <svc> --tail=200` (`json-file`, ротация 10m×3).
- Централизованно: Loki (retention 7d), Alloy (только `payment-stack-*`).
- Корреляция: `request_id` (grep / Loki).