# Claude Skills

Персональная коллекция Skills для [Claude Code](https://claude.com/claude-code) — модульных подсказок и инструкций, которые Claude автоматически подгружает по триггерам в задачах.

## Установка

На новом устройстве, если папка `~/.claude/skills/` ещё не существует:

```bash
git clone git@github.com:Nemagu/claude_skills.git ~/.claude/skills
```

Если папка уже есть и в ней что-то лежит — перенеси/удали её содержимое или клонируй репо в другое место и подключи через symlink:

```bash
git clone git@github.com:Nemagu/claude_skills.git ~/dev/claude_skills
mv ~/.claude/skills ~/.claude/skills.bak    # бэкап старого
ln -s ~/dev/claude_skills ~/.claude/skills
```

Для клонирования по SSH нужен зарегистрированный SSH-ключ на GitHub.

## Структура

Каждый скил — отдельная поддиректория с файлом `SKILL.md` (точка входа, YAML-frontmatter с именем и триггерами активации) и опциональной папкой `references/` с углублёнными материалами по отдельным аспектам.

```
<skill-name>/
├── SKILL.md
└── references/             ← опционально
    ├── <topic-1>.md
    └── <topic-2>.md
```

## Список скилов

### `python-ddd-domain-layer-writing`

Проектирование и правка доменного слоя в Python-проекте по DDD/гексагональной архитектуре. Триггеры — добавление или изменение агрегата, проекции, value object, доменного сервиса, фабрики, абстрактного repository-интерфейса в `domain/`; реализация инвариантов и поведения сущности; работа с версионированием, доменными ошибками и состояниями агрегата.

### `python-gitlab-ci-pipeline`

Создание и правка `.gitlab-ci.yml` для Python-сервисов на uv (DDD/CQRS-бэкенды). Триггеры — добавление/изменение джоб lint, test (unit и integration), build образа; настройка кэша uv, стадий, `workflow.rules`; сборка docker-образа в CI (Kaniko, теги по ветке, registry mirror); подключение отчётов (JUnit, coverage, code quality) и security-гейтов (bandit, pip-audit, trivy). Тесты сам скил не пишет — для этого `python-pytest-testing`.

### `python-fastapi-background-worker`

Проектирование или реализация background worker в Python-приложении на FastAPI. Триггеры — фоновые задачи через lifecycle startup/shutdown, очереди, конкурентность, retry/idempotency, observability и обязательное использование uvloop как runtime event loop.

### `python-nats-background-worker`

Проектирование или реализация background worker на Python поверх NATS и JetStream. Триггеры — асинхронная обработка событий/команд, durable consumer, ack and retry, idempotency, DLQ, graceful shutdown, observability и обязательное использование uvloop как runtime event loop.

### `python-postgres-repository-writing`

Написание или ревью Postgres-репозиториев на Python (psycopg) в проектах с DDD/CQRS и порт-адаптерной архитектурой. Триггеры — реализация save/read-репозиториев, mapping DB-to-domain, batch-сохранение, безопасные SQL-запросы без f-строк, обработка конфликтов, эффективный list/count с пагинацией.

### `python-pytest-testing`

Проектирование, написание или проверка автотестов на Python через pytest и pytest-cov. Триггеры — добавление/правка unit и integration тестов, организация фикстур и фабрик, параметризация через pytest.mark.parametrize, улучшение структуры тестов и стабильный запуск через единый guard-скрипт.

### `python-repository-documentation`

Документирование Python-репозиториев в прикладных сервисах. Триггеры — описание архитектуры, модулей, публичных методов и контрактов; написание docstring на русском языке в кратком стиле; оформление README, env.example и примеров конфигов; синхронизация документации с изменениями кода.

## Как добавить новый скил

1. Создай директорию `<skill-name>/` в корне репо.
2. Положи `SKILL.md` с frontmatter:
   ```yaml
   ---
   name: <skill-name>
   description: <одно-два предложения о том, когда Claude должен активировать скил>
   ---
   ```
3. По необходимости — добавь `references/<topic>.md` с углублёнными разделами.
4. Обнови этот README — добавь новый скил в список.
5. Закомить и запушь.

## Как обновить существующий скил

1. Отредактируй файлы в нужной поддиректории.
2. Если меняешь публичный API скила (триггеры, имя, состав references) — синхронизируй описание в этом README.
3. Закомить и запушь.

Изменения подхватываются Claude'ом сразу — перезапуск не нужен.
