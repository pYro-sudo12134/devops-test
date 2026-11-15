# [Payment Stack (Northwind Transfer) — DevOps test](https://github.com/pYro-sudo12134/devops-test)

Воспроизводимый стек международных переводов: api (FastAPI), worker (RabbitMQ),
PostgreSQL (миграции one-shot), Vault (dev), reverse-proxy (nginx), mock-provider
(внешний «провайдер», HTTPS), наблюдаемость (Prometheus/Alertmanager/Grafana/Loki).

## Требования (чистая машина)
- Docker + Compose v2
- Git, make, bash (Linux/macOS/WSL/MINGW)
- интернет (pull образов/зависимостей)

## Быстрый старт (stage)
```bash
cp deploy/.env.example deploy/.env      # заполнить секреты
make deploy ENV=stage                   # бизнес-стек (api, worker, db, rabbitmq, vault, mock-provider, nginx)
make deploy-observability ENV=stage     # + Prometheus/Alertmanager/Grafana/reporting-ui/Loki/Alloy
make status
make smoke
```

## Секреты
`deploy/.env` (не коммитится, `.gitignore`):
- `VAULT_DEV_ROOT_TOKEN` — root-токен Vault dev (локальный stage).
- `DB_PASSWORD`, `RABBITMQ_PASSWORD`, `PROVIDER_API_KEY`, `GRAFANA_ADMIN_PASSWORD`.
- `IMAGE_PREFIX` — реестр (локально `northwind`/`ghcr.io/<owner>`, CI — `ghcr.io/<owner>`).

Цепочка: `.env` → `seed.sh` → **Vault** → `render-env.sh` → `runtime.env` (chmod 600) → контейнеры.
В CI (`SECRETS_SOURCE=env`) — из `env:` job'а (без Vault).

## Проверка
```bash
# API (порт из deploy/env/stage.env, напр. 8094)
curl -X POST http://127.0.0.1:8094/transfers -H 'Content-Type: application/json' \
  -H 'X-Request-Id: demo-1' \
  -d '{"amount":"100.00","currency":"RUB","recipient":"TH1234567890"}'
curl http://127.0.0.1:8094/transfers/<id>
```
- API: `http://127.0.0.1:${API_PORT}/health` (проверяет БД+RabbitMQ), `/metrics`.
- Grafana: `http://127.0.0.1:8090` (reporting-ui → Grafana), `admin` / `GRAFANA_ADMIN_PASSWORD`.
- Prometheus: `http://127.0.0.1:9090` (targets/alerts); Alertmanager: `http://127.0.0.1:9093`.
- Loki: `http://127.0.0.1:3100` (через Grafana Explore); Alloy UI: `http://127.0.0.1:12345`.
- RabbitMQ mgmt: `http://127.0.0.1:15672` (`payments`/<RABBITMQ_PASSWORD>).

## CI / CD
- **CI** (GitHub Actions, `ubuntu-latest`, публичный репо): lint → test → build → **Trivy** (fail on fixable CRITICAL/HIGH) → push GHCR → **compose-smoke** (тот же `deploy.sh`, `SECRETS_SOURCE=env`, `PULL_IMAGES=1`).
- **Доказательство прогона:** [ссылка](https://github.com/pYro-sudo12134/devops-test/actions/runs/43715093611).
- **CD** — `make deploy ENV=stage` (идемпотентный, миграции one-shot, smoke + автооткат). В CI в «прод» не деплоим (прод-инфры нет — ASSUMPTIONS/LIMITS).

## Документация
- `ARCHITECTURE.md` — схема, поток деплоя, границы доверия.
- `RUNBOOK.md` — деплой, откат, секреты, очередь/DLQ, БД, Grafana, PENDING, request_id, ротация.
- `DECISIONS.md` — ключевые решения + где ИИ ошибался.
- `ASSUMPTIONS.md` — неоднозначности и как разрешили.
- `LIMITS.md` — что не сделано (честно).

## Команды
`make deploy|deploy-observability|down|status|logs|migrate|smoke|backup|restore|verify-restore|rotate|lint|test`