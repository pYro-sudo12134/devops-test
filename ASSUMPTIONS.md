# ASSUMPTIONS

- **Vault dev-режим** оставлен: в рамках теста полноценный Vault с persistent storage — оверкилл. Ограничение — в LIMITS.
- **`deploy/.env` vs `runtime.env`**: `.env` — для подстановки `${...}` в compose; `runtime.env` — `env_file` для контейнеров. Оба не коммитятся. В README объяснено.
- **CD = `make deploy`**, не GitHub Actions job: нет 24/7 раннера; CI проверяет тот же путь через compose-smoke.
- **Секреты в CI** — переменные раннера (в проде были бы GitHub Secrets); для теста явные значения.
- **`003_add_amount_minor` необратим** (DROP COLUMN amount): откат схемы — только forward-fix; описано в RUNBOOK.
- **`reporting-ui`** — не часть основного стека по легенде; отложен на L4.
- **Windows-хост**: `.gitattributes` с `eol=lf`; CRLF в `*.sh` — известная ловушка, закрыта.