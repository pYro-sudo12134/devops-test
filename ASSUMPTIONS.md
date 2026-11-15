# ASSUMPTIONS

- Vault dev-режим оставлен: полноценный Vault с persistent storage — оверкилл для теста.
- `deploy/.env` — для подстановки `${...}` в compose; `runtime.env` — `env_file` для контейнеров. Оба не коммитятся.
- CD = `make deploy`, не GitHub Actions job: нет 24/7 раннера; CI проверяет тот же путь через compose-smoke.
- Секреты в CI — тестовые `ci-*` в `env:` (не боевые); в проде были бы GitHub Secrets/Vault persistent. `GITHUB_TOKEN` — для GHCR.
- `003_add_amount_minor` необратим (DROP COLUMN amount): откат схемы — forward-fix, в RUNBOOK.
- `reporting-ui` — не часть основного стека по легенде; отложен на L4.
- Windows-хост: `.gitattributes` eol=lf; CRLF в `*.sh` закрыт.
- Секреты: «боевых» нет, потому что нет боевого деплоя; механизм (Vault/env/Secrets) — демонстрационный.
- Outbox/CDC — **рекомендация**, не реализовано: изменение приложения (транзакции/outbox/поллер/CDC), вне DevOps-зоны теста.