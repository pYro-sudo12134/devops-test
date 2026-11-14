import logging
from pathlib import Path

import psycopg

from .config import load_settings

log = logging.getLogger("migrate")

MIGRATION_LOCK_KEY = 0x5EED_0001  # 1592393729


def run(dsn, directory):
    with psycopg.connect(dsn, autocommit=True) as conn:
        conn.execute("SET lock_timeout = '30s'")
        conn.execute("SELECT pg_advisory_lock(%s)", (MIGRATION_LOCK_KEY,))
        try:
            conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)")
            applied = {row[0] for row in conn.execute("SELECT version FROM schema_migrations")}
            for path in sorted(Path(directory).glob("*.sql")):
                if path.name in applied:
                    continue
                with conn.transaction():
                    conn.execute(path.read_text())
                    conn.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (path.name,))
                log.info("applied %s", path.name)
        finally:
            conn.execute("SELECT pg_advisory_unlock(%s)", (MIGRATION_LOCK_KEY,))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    run(load_settings().dsn, "migrations")