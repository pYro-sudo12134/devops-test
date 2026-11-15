# DECISIONS

## L1 — гигиена
- Убран `docker compose down -v` (уничтожал тома) → `up -d --wait`.
- Pinned-версии (postgres:16.4, rabbitmq:3.13.7-management, nginx:1.27.3, vault:1.17.6, prometheus:v2.54.1, alertmanager:v0.27.0, grafana:11.2.0, loki:3.1.1, alloy:v1.4.2, python:3.12-slim).
- Multi-stage + non-root; `base`-stage с `--only-upgrade zlib1g` (точечно, потому что подбирая версии python было замечено, что zlib1g все той же самой версии, которая признана с уязвимостями, как было выяснено с помощью trivy).
- `/health` проверяет БД+RabbitMQ (503); healthcheck через python (в slim нет curl).
- `depends_on: condition: service_healthy`; stage/prod без копипасты (override).
- Секреты: `.env.example` (плейсхолдеры), `runtime.env` в `.gitignore` + chmod 600; дефолтный root-токен Vault убран; `.gitattributes` eol=lf.

## L2 — доставка
- Миграции one-shot `run --rm --no-deps -T migrate` до раскатки (не из реплик); `pg_advisory_lock` + `lock_timeout=30s`.
- `migrate` — отдельный образ/тег `payment-api-migrate` (target `migrate`), профиль `tools`.
- `certs-init` (root) chown `provider-certs`; mock-provider (non-root) пишет; worker читает (`:ro`); `service_completed_successfully`; **не** в профиле.
- `APP_VERSION` из git; GHCR; публичные пакеты (тест).
- CI: lint→test→build→trivy (fail on fixable CRITICAL/HIGH)→push GHCR→compose-smoke (тот же deploy.sh). CD-workflow нет (нет 24/7 раннера); CD=`make deploy` руками.
- Smoke + автооткат (`rollback.sh $PREV_VERSION`); `.last_version`.
- `backup.sh` — `payments`, ротация 7; `restore.sh` + `verify-restore.sh` (проверенное восстановление).
- `SECRETS_SOURCE=vault|env`; `touch runtime.env` до compose; `-T` для run; `APP_VERSION:-dev` (down/config); `:?` у секретов убран (parse), обязательность — `deploy.sh`/`require_runtime_secret`.
- `reverse-proxy`: `resolver 127.0.0.11` + `set $api_upstream` (не кэширует IP; нет 502 после recreate api); `map` для `X-Request-Id`.
- `smoke.sh`: `API_PORT` из `deploy/env/$ENV.env` (если не в env), `--max-time`/retry (`/health`).

## L3 — секреты и надёжность
- DLQ `transfers.dlq` + DLX `transfers.dlx` + retry `transfers.retry` (TTL 10s, DLX=default → transfers). `MAX_RETRIES` из env; `x-retry-count` (републикация, requeue не меняет headers); после N → `nack(requeue=False)` → DLQ. `worker_messages_total{result}`.
- Топология — `declare_topology` (env), **не** definitions (трижды роняли: `import_backend=local_files` undef, vhost, ACCESS_REFUSED). Если бы это был kubernetes, можно было бы решить этот вопрос с помощью helm, есть готовые чарты, где просто достаточно подставить значения с минимальными усилиями, либо же модифицируя configmapы и секреты с помощью kustomize. Пароль RabbitMQ — только env.
- `provider.py`: `verify=False` → `verify=PROVIDER_CA_BUNDLE` (TLS к mock-provider). `urllib3.disable_warnings()` убран.
- `request_id` сквозной: nginx (`$request_id`/клиент, `map`) → api → broker (`x-request-id`) → worker → provider (`X-Request-Id`) + логи; в ответе `X-Request-Id`; retry сохраняет. `health`/`metrics` — без.
- `pika` → WARNING; свой логгер по `LOG_LEVEL`; `Settings` repr не логирует пароли.
- Grafana admin — Vault (seed/render/export); `GF_SECURITY_ADMIN_PASSWORD` — initial; сброс `grafana cli`.
- Ротация `PROVIDER_API_KEY` — `rotate-provider-key.sh` (только внешний, остальные во внутреннем секторе; DB/MQ — прод, LIMITS).
- Бэкап + `verify-restore` (проверенное восстановление).

## L4 — наблюдаемость
- RED (api): `api_requests_total`, `http_request_duration_seconds`, `api_in_flight` (middleware). Бизнес: `transfers_created_total`, `transfers_total{status}`, `oldest_pending_age_seconds`.
- RabbitMQ per-queue: `RABBITMQ_PROMETHEUS_RETURN_PER_OBJECT_METRICS=true` → `rabbitmq_queue_messages_ready{queue="transfers.dlq"}` (без — агрегат).
- Алерты: `oldest_pending_age_seconds>300` (5м), `rabbitmq_queue_messages_ready{queue="transfers.dlq"}>0` (5м), `up{job=api|worker}==0` (2м), `absent(up)` (5м, dead man's switch).
- Alertmanager без интеграций (UI); в проде — slack/pagerduty/webhook.
- Дашборд «Payments»: transfers, oldest_pending (60/300), DLQ (per-queue), by status, up, **Logs** (Loki) — за 10с.
- Loki + Alloy: docker API (sock), `keep` (`payment-stack-*`), `service_name`/`owner`, retention 7d; `reject_old_samples` убран.
- `docker-compose.reporting.yml` — override; `make deploy` / `make deploy-observability`; `--remove-orphans` убран; метки `owner: payments|analytics`; reporting-ui (nginx → Grafana).

## Dual-write / outbox / CDC — найдено, описано, рекомендовано (не реализовано)
- api: `INSERT` + `publish` — две транзакции; publish fail → PENDING без сообщения.
- Рекомендация (прод): transactional outbox + relay/CDC (Debezium). Этого можно добиться, если создать отдельную таблицу в БД, например, PostgreSQL, храня в ней информацию о запросе, используя таймеры для повторной отправки. Тем самым реализуется машина состояния для сообщений. Однако, такие задачи, как мне известно, делает разработчик обычно, но и не то, что бы это нереально реализовать.

## Где ИИ ошибался (и как поймали)
1. `:?` у `VAULT_DEV_ROOT_TOKEN`/`DB_PASSWORD`/`RABBITMQ_PASSWORD` в compose — валидация **при парсинге** для всех сервисов (CI падал на vault/db, которые не поднимались). Убрали, обязательность — `deploy.sh`.
2. `env_file: runtime.env` валидируется при парсинге → `up vault` падал до `render-env.sh`; фикс — `touch runtime.env`.
3. `POSTGRES_PASSWORD` vs `DB_PASSWORD` — падало на `required()`; унифицировали.
4. Один тег — один образ: `migrate` и `api` делили `payment-api`, migrate запускал runtime (uvicorn) → зависание. Разные теги + target.
5. `docker compose run` без `-T` виснет в CI.
6. `up --wait` считает `exited` провалом (migrate не в `service_completed_successfully`) → профиль `tools`.
7. `certs-init` в профиле → «undefined service»; не в профиле.
8. GHCR: `github.repository_owner.lowercase` не существует, это просто пустой аттрибут будет.
9. Trivy: `zlib1g`/`starlette`; `--only-upgrade zlib1g` в `builder` (не `runtime`!) — не копируется; `base`-stage. `starlette==1.3.1`. Также ИИ не знал актуальные версии Trivy, тем самым пришлось подкорректировать, зайдя в релизы.
10. `Settings` логировался с паролями, потому что в лог просто передавалась строковое представление — убрано.
11. `GRAFANA_ADMIN_PASSWORD` безусловно в `env` — CI (без reporting) `unbound`; `:-` + require только для reporting.
12. `GF_SECURITY_ADMIN_PASSWORD` — только initial (том grafana-data); сброс `grafana cli`.
13. `smoke.sh` 502 после recreate api (nginx кэшировал upstream) → `resolver`+переменная; `smoke.sh` брал `8080` вместо `8094` (API_PORT из env) → чтение `deploy/env/$ENV.env`.
14. Loki: `reject_old_samples` (400 на старые) + kind логи из моей машины → `keep` (`payment-stack-*`), `reject_old_samples` убран.
15. RabbitMQ без per-queue (`queue` лейбл) → написано в конфиге `rabbitmq.conf`.
16. `make verify-restore` — относительный путь бэкапа → абсолютный (`backup.sh`).
17. Конфигурация приложений была написана хардкодом, поэтому попросил внедрить конфиги. Они уже были, но конфигурация dlq, например, была написана сначала хардкодом.