# ASSUMPTIONS

- **Vault dev** (root-токен, in-memory) — разрешён; persistent/AppRole — прод (LIMITS).
- **CD = `make deploy`**, не GitHub Actions job: нет 24/7 раннера; CI проверяет compose-smoke, причем само задание прямо говорит, что CD сделать через make, но не сказано, как. Однако если меня будут проверять, а я выключу свой ноутбук, то выйдет, что я получу 0 просто потому что.
- **Секреты в CI** — тестовые `ci-*` в `env:` (эфемерный стек). `GITHUB_TOKEN` — GHCR.
- **`003_add_amount_minor` необратим** (DROP COLUMN amount): откат схемы — forward-fix.
- **`reporting-ui`** — nginx → Grafana (не статика); метка `owner: analytics`, судя по изначальной задумке docker-compose.reporting.yml, ожидались метки.
- **Dual-write** (INSERT+publish): outbox/CDC рекомендованы, не реализованы (вне DevOps-зоны, но имеет смысл реализовать в целом, чтобы висячие сообщения были обработаны).
- **`request_id`** — был задуман (nginx `$request_id`), судя по reverse-proxy/nginx.conf, иначе зачем он был нужен, api не читал; доделали сквозной.
- **TLS**: клиент→nginx — HTTP (прод — TLS-терминация); внутри сети — plain (изолирована); TLS к mock-provider — проверяется.
- **Windows-хост**: `.gitattributes` eol=lf.
- **`deploy/.env` vs `runtime.env`**: `.env` — `${...}` в compose; `runtime.env` — `env_file`. Оба не коммитятся.
- **Grafana admin** — Vault (initial); fallback `admin` только для down/config.
- **`API_PORT`** — из `deploy/env/<env>.env` (smoke читает, если не в env, эти файлы я не убирал, потому что в них ничего не хранится ценного по типу паролей).
- **`mock-provider`** — имитация внешнего провайдера (self-signed TLS, `/admin/fail-mode` — для учений; не часть Northwind).