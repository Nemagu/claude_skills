# Config Files and Infrastructure in Tests

## Two Modes of Integration Infrastructure

Интеграционные тесты должны поддерживать два режима работы:

- **local mode** — фикстура поднимает зависимости (`docker compose up`), ждёт готовности и сама же останавливает их в finally.
- **external mode** — инфраструктура уже поднята снаружи (например, в CI как services контейнеры). Фикстура только подключается и не запускает свои контейнеры.

Переключатель — переменная окружения `INTEGRATION_USE_EXTERNAL_INFRA`:

- не задана / `0` → local mode
- `1` → external mode

В external mode параметры подключения берутся из переменных с префиксом `INTEGRATION_*` (имена ниже — рекомендация по умолчанию; если в проекте уже есть конвенция, спроси пользователя и используй её):

```
INTEGRATION_PG_HOST
INTEGRATION_PG_PORT
INTEGRATION_PG_USER
INTEGRATION_PG_DATABASE
INTEGRATION_PG_PASSWORD
INTEGRATION_NATS_HOST
INTEGRATION_NATS_PORT
```

> Скил намеренно не описывает, кто и как выставляет эти переменные снаружи — это ответственность отдельного слоя (CI-конфигурация, dev-окружение и т. п.).

---

## Временные файлы

Все временные файлы одного тестового прогона размещаются в изолированной папке:

```
/tmp/<project_name>/
```

- `<project_name>` — имя сервиса (например, `users_service`)

Внутри папки имена файлов содержат runtime-id (uuid7), чтобы параллельные прогоны не конфликтовали:

```
/tmp/<project_name>/runtime-config-<uuid>.yaml
/tmp/<project_name>/db-password-<uuid>.txt
/tmp/<project_name>/docker-compose-<uuid>.yaml
```

После завершения сессии фикстура **удаляет свои файлы** в `finally`. Если папка `/tmp/<project_name>/` после уборки пуста — её тоже удаляем. Это держит `/tmp` в чистом состоянии и при этом изолирует параллельные прогоны.

> При диагностике падения можно временно отключить уборку (например, переменной окружения `KEEP_INTEGRATION_TMP=1`) — это не часть скила, а локальный приём.

---

## Поиск свободного порта

Используй `socket` для получения случайного свободного порта — без хардкода:

```python
import secrets
import socket


def find_free_port() -> int:
    """Возвращает свободный TCP-порт в диапазоне 2000-65000."""
    min_port = 2000
    max_port = 65000
    for _ in range(2000):
        port = secrets.randbelow(max_port - min_port + 1) + min_port
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                continue
            return port
    raise RuntimeError("Не удалось подобрать свободный порт")
```

---

## Ожидание готовности через TCP-polling

TCP-polling надёжнее HTTP: работает для любого сервиса (postgres, nats, redis) без зависимости от HTTP-эндпоинта.

```python
import socket
import time


def wait_for_tcp(host: str, port: int, timeout: float = 60.0, interval: float = 1.0) -> None:
    """Блокирует до появления TCP-соединения или бросает TimeoutError."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=1.0):
                return
        except OSError:
            time.sleep(interval)
    raise TimeoutError(f"Сервис {host}:{port} не стал доступен за {timeout}s")
```

Для Postgres лучше использовать `psycopg.connect` + `SELECT 1`, для NATS — проверку, что в первом фрейме пришло `INFO`, чтобы не считать готовым полуоткрытый сокет.

---

## Canonical Integration Fixture

Канонический паттерн интеграционных тестов:

- session-scoped фикстура `integration_runtime` — единственная точка, которая поднимает или подключается к инфраструктуре, применяет миграции и отдаёт `settings`.
- function-scoped autouse-фикстура `clean_db` — очищает данные перед каждым тестом.
- остальные фикстуры зависят от `integration_runtime` напрямую или транзитивно.

Пример (двухрежимный, с docker compose в local mode):

```python
import os
import secrets
import shutil
import socket
import subprocess
from collections.abc import Generator
from pathlib import Path
from uuid import uuid7

import psycopg
import pytest

from infrastructure.config import IntegrationSettings  # пример
from infrastructure.db.postgres.apply_migrations import apply_migrations

PROJECT_NAME = "projects_service"
TEST_RUNTIME_DIR = Path("/tmp") / PROJECT_NAME

DEFAULT_PG_USER = "projects_test"
DEFAULT_PG_DB = "projects_test"

DOCKER_COMPOSE_TEMPLATE = """services:
  postgres:
    image: postgres:18-alpine
    environment:
      POSTGRES_USER: {pg_user}
      POSTGRES_DB: {pg_db}
      POSTGRES_PASSWORD: {pg_password}
    ports:
      - "{pg_port}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U {pg_user} -d {pg_db}"]
      interval: 2s
      timeout: 3s
      retries: 30
      start_period: 2s

  nats:
    image: nats:2.12-alpine
    command: ["-js", "-m", "8222"]
    ports:
      - "{nats_port}:4222"
"""


def _use_external_infra() -> bool:
    return os.environ.get("INTEGRATION_USE_EXTERNAL_INFRA", "0") == "1"


@pytest.fixture(scope="session")
def integration_runtime() -> Generator[IntegrationSettings, None, None]:
    use_external = _use_external_infra()

    if not use_external and shutil.which("docker") is None:
        pytest.skip("docker не найден, интеграционные тесты пропущены")

    runtime_id = uuid7()
    TEST_RUNTIME_DIR.mkdir(parents=True, exist_ok=True)

    compose_file: Path | None = None
    project_name: str | None = None

    if use_external:
        pg_host = os.environ["INTEGRATION_PG_HOST"]
        pg_port = int(os.environ["INTEGRATION_PG_PORT"])
        pg_user = os.environ.get("INTEGRATION_PG_USER", DEFAULT_PG_USER)
        pg_db = os.environ.get("INTEGRATION_PG_DATABASE", DEFAULT_PG_DB)
        pg_password = os.environ["INTEGRATION_PG_PASSWORD"]
        nats_host = os.environ["INTEGRATION_NATS_HOST"]
        nats_port = int(os.environ["INTEGRATION_NATS_PORT"])
    else:
        pg_host = "127.0.0.1"
        pg_port = find_free_port()
        pg_user = DEFAULT_PG_USER
        pg_db = DEFAULT_PG_DB
        pg_password = secrets.token_urlsafe(24)
        nats_host = "127.0.0.1"
        nats_port = find_free_port()
        project_name = f"{PROJECT_NAME}-tests-{runtime_id}"
        compose_file = TEST_RUNTIME_DIR / f"docker-compose-{runtime_id}.yaml"
        compose_file.write_text(
            DOCKER_COMPOSE_TEMPLATE.format(
                pg_user=pg_user,
                pg_db=pg_db,
                pg_password=pg_password,
                pg_port=pg_port,
                nats_port=nats_port,
            ),
            encoding="utf-8",
        )
        subprocess.run(
            ["docker", "compose", "-p", project_name, "-f", str(compose_file), "up", "-d"],
            check=True,
        )

    settings = IntegrationSettings(
        pg_host=pg_host, pg_port=pg_port, pg_user=pg_user,
        pg_db=pg_db, pg_password=pg_password,
        nats_host=nats_host, nats_port=nats_port,
    )

    try:
        wait_for_tcp(pg_host, pg_port)
        wait_for_tcp(nats_host, nats_port)
        apply_migrations(settings.db)
        yield settings
    finally:
        if compose_file is not None and project_name is not None:
            subprocess.run(
                ["docker", "compose", "-p", project_name, "-f", str(compose_file),
                 "down", "--remove-orphans"],
                check=False,
            )
            compose_file.unlink(missing_ok=True)
        if TEST_RUNTIME_DIR.exists() and not any(TEST_RUNTIME_DIR.iterdir()):
            shutil.rmtree(TEST_RUNTIME_DIR, ignore_errors=True)
```

---

## Cleaning Database Between Tests (Dynamic TRUNCATE)

Жёсткий список таблиц в `TRUNCATE` рассинхронизируется при каждом изменении схемы. Лучше получать список из `pg_tables` и исключать служебные таблицы инструмента миграций (`yoyo_*`):

```python
import pytest_asyncio
from psycopg import AsyncConnection
from psycopg.rows import dict_row


_TABLES_QUERY = """
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename NOT LIKE 'yoyo_%'
"""


@pytest_asyncio.fixture(autouse=True)
async def clean_db(postgres_settings) -> None:
    conn = await AsyncConnection.connect(
        conninfo=postgres_settings.url,
        row_factory=dict_row,
        autocommit=False,
    )
    try:
        async with conn.cursor() as cur:
            await cur.execute(_TABLES_QUERY)
            tables = [row["tablename"] for row in await cur.fetchall()]
        if tables:
            quoted = ", ".join(f'"{t}"' for t in tables)
            await conn.execute(f"TRUNCATE TABLE {quoted} RESTART IDENTITY CASCADE")
            await conn.commit()
    finally:
        await conn.close()
```

Имена таблиц приходят из системного каталога Postgres и квотируются — это безопасно, f-строка не подставляет пользовательский ввод.

> Если в схеме появляются partitioned-таблицы или таблицы в нескольких схемах — расширь запрос (`schemaname IN (...)`) или явно перечисли исключения.

---

## YAML-конфиг приложения для тестов

Если приложение читает настройки из YAML через `CONFIG_FILE`, фикстура создаёт временный конфиг и выставляет переменную окружения:

```python
@pytest.fixture(scope="session")
def app_config_file(integration_runtime) -> Path:
    config = TEST_RUNTIME_DIR / f"runtime-config-{uuid7()}.yaml"
    config.write_text(_render_config(integration_runtime), encoding="utf-8")
    os.environ["CONFIG_FILE"] = str(config)
    return config
```

Если нужна изоляция между тестами (например, разные конфиги в разных кейсах), используй `monkeypatch.setenv` вместо прямого `os.environ`.
