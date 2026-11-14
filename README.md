# Payment Stack
cd deploy && ./deploy.sh stage
curl -X POST http://localhost:8080/transfers -H 'Content-Type: application/json' -d '{"amount":"100.00","currency":"RUB","recipient":"TH1234567890"}'

## Быстрая проверка
- Локально: `cp deploy/.env.example deploy/.env` (заполнить), `make deploy ENV=stage`, `make status`.
- CI: push в `main`; зелёный [run](https://github.com/pYro-sudo12134/devops-test/actions/runs/43644381927) в Actions.
- Бэкап: `make backup`, проверка: `./scripts/verify-restore.sh`.
- Откат: `./deploy/rollback.sh <version>` (схема не откатывается — см. RUNBOOK).