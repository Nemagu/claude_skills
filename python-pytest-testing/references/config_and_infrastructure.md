# Config Files and Infrastructure in Tests

## Временные файлы

Все временные файлы одного тестового прогона размещаются в изолированной папке:

```
/tmp/<project_name>/<session_uuid>/
```

- `<project_name>` — имя сервиса (например, `users_service`)
- `<session_uuid>` — UUID, генерируемый один раз за сессию; изолирует параллельные прогоны

Файлы **не удаляются** после прогона — они остаются для отладки.

### Session UUID fixture

```python
import uuid
import pytest
from pathlib import Path

PROJECT_NAME = "users_service"

@pytest.fixture(scope="session")
def session_tmp_dir() -> Path:
    """Создаёт изолированную папку для временных файлов текущей тестовой сессии."""
    path = Path("/tmp") / PROJECT_NAME / str(uuid.uuid7())
    path.mkdir(parents=True, exist_ok=True)
    return path
```

### Использование для файлов конфигурации

```python
@pytest.fixture(scope="session")
def jwt_key_files(rsa_keys, session_tmp_dir: Path) -> tuple[Path, Path]:
    private_path = session_tmp_dir / "jwt_private.pem"
    public_path = session_tmp_dir / "jwt_public.pem"
    private_pem, public_pem = rsa_keys
    private_path.write_bytes(private_pem)
    public_path.write_bytes(public_pem)
    return private_path, public_path
```

### YAML-конфиг приложения

Если приложение читает настройки из YAML через `CONFIG_FILE`, создай файл и задай переменную окружения:

```python
import os
import pytest
from pathlib import Path

@pytest.fixture(scope="session")
def app_config_file(session_tmp_dir: Path, jwt_key_files: tuple[Path, Path]) -> Path:
    private_path, public_path = jwt_key_files
    config = session_tmp_dir / "config.yaml"
    config.write_text(f"""\
jwt:
  private_key_file: {private_path}
  public_key_file: {public_path}
  algorithm: RS256
  issuer: test
  audience: test_api
""")
    os.environ["CONFIG_FILE"] = str(config)
    return config
```

> Если нужна изоляция между тестами, используй `monkeypatch.setenv` вместо прямого `os.environ`.

---

## Поиск свободного порта

Используй `socket` для получения случайного свободного порта — без хардкода:

```python
import socket

def find_free_port() -> int:
    """Возвращает свободный TCP-порт, выделенный ОС."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return s.getsockname()[1]
```

---

## Поднятие инфраструктуры (Docker Compose)

Compose-файл создаётся в `session_tmp_dir` с уникальным именем проекта:

```python
import subprocess
import uuid
from pathlib import Path
import pytest

@pytest.fixture(scope="session")
def compose_project(session_tmp_dir: Path) -> str:
    """Поднимает инфраструктуру через docker compose и возвращает имя проекта."""
    pg_port = find_free_port()
    project_name = f"test_{uuid.uuid7().hex[:8]}"

    compose_file = session_tmp_dir / "docker-compose.yml"
    compose_file.write_text(f"""\
services:
  postgres:
    image: postgres:18
    environment:
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
      POSTGRES_DB: test
    ports:
      - "{pg_port}:5432"
""")

    subprocess.run(
        ["docker", "compose", "-p", project_name, "-f", str(compose_file), "up", "-d"],
        check=True,
    )

    wait_for_tcp("localhost", pg_port)

    yield project_name

    subprocess.run(
        ["docker", "compose", "-p", project_name, "-f", str(compose_file), "down", "-v"],
        check=True,
    )
```

---

## Ожидание готовности через TCP-polling

TCP-polling надёжнее HTTP: работает для любого сервиса (postgres, nats, redis) без зависимости от HTTP-эндпоинта.

```python
import socket
import time

def wait_for_tcp(host: str, port: int, timeout: float = 30.0, interval: float = 0.5) -> None:
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
