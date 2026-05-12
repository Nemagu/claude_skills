---
name: python-gitlab-ci-pipeline
description: Используй при создании или правке .gitlab-ci.yml для Python-сервисов на uv (DDD/CQRS-бэкенды). Триггеры — добавление/изменение джоб lint, test (unit и integration), build образа; настройка кэша uv, стадий, workflow.rules; сборка docker-образа в CI (Kaniko, теги по ветке, registry mirror); подключение отчётов (JUnit, coverage, code quality) и security-гейтов (bandit, pip-audit, trivy). Не применять для написания самих тестов — для этого есть python-pytest-testing.
---

# Python GitLab CI Pipeline

Скил про `.gitlab-ci.yml` прикладного Python-сервиса на `uv`: стадии, джобы, кэш, отчёты, сборка образа. Сам скил тесты не пишет — за «что именно запускать в тестовых джобах» отвечает `python-pytest-testing`; здесь только то, как обернуть это в CI.

## Quick Start

1. Опиши стадии: `lint → test → build → scan`.
2. Сделай `workflow.rules` для дедупа пайплайнов branch/MR.
3. Заведи `default:`-блок: `image: python:3.14-slim` + установка `uv` + кэш по `uv.lock`, и `variables:` с `UV_*`.
4. Стадия `lint`: `ruff` (+ codequality-отчёт), `ruff-format`, `bandit` (gate), `deps-audit` (gate).
5. Стадия `test`: `unit-tests`, затем `integration-tests` (с `services:` и `INTEGRATION_USE_EXTERNAL_INFRA=1` — сверься с `python-pytest-testing`). Оба отдают JUnit + cobertura.
6. Стадия `build`: `build-image` на Kaniko — тег `dev` на `develop`, `prod` на `main`, плюс `$CI_COMMIT_SHORT_SHA`; на других ветках не билдим.
7. Стадия `scan`: `container-scan` (Trivy по собранному образу, gate на HIGH/CRITICAL).
8. Прогони пайплайн, убедись что отчёты подхватились, зафиксируй DoD.

Готовый эталонный файл целиком — в [pipeline_skeleton.md](references/pipeline_skeleton.md). Бери его как стартовую точку и адаптируй под проект.

## Структура пайплайна

Стадии идут строго по зависимостям, внутри стадии джобы параллельны:

- **`lint`** — статика и быстрые гейты: `ruff check`, `ruff format --check`, `bandit` (SAST), `pip-audit` (зависимости). Всё параллельно, падает рано и дёшево.
- **`test`** — `unit-tests`, потом `integration-tests`. Unit раньше: они быстрее и без инфраструктуры, нет смысла поднимать Postgres/NATS, если упали базовые юниты. (Если хочется явный DAG — см. `needs:` в [pipeline_skeleton.md](references/pipeline_skeleton.md).)
- **`build`** — `build-image`: собираем и пушим образ. Только после зелёных lint+test — в реестр не должен попадать образ из непрошедшего кода.
- **`scan`** — `container-scan`: сканируем уже собранный образ. Отдельная стадия, потому что нужен артефакт билда.

Имя стадии — `lint`, не `check` (так в `companies/backend` и `users/backend`; единообразие важнее).

## `default:` и `variables:`

Один общий блок, чтобы не дублировать установку `uv` и кэш по джобам:

```yaml
default:
  image: python:3.14-slim
  before_script:
    - pip install --no-cache-dir --disable-pip-version-check --root-user-action=ignore uv
  cache:
    key:
      files:
        - uv.lock
    paths:
      - .uv-cache/

variables:
  UV_CACHE_DIR: $CI_PROJECT_DIR/.uv-cache
  UV_LINK_MODE: copy
  UV_FROZEN: "1"
  UV_NO_PROGRESS: "1"
  PIP_DISABLE_PIP_VERSION_CHECK: "1"
  PIP_NO_CACHE_DIR: "1"
```

- Кэшируем `.uv-cache/` (скачанные дистрибутивы), а не `.venv/`. Каждая джоба делает свой `uv sync` с нужной группой зависимостей (`--no-install-project`, без самого проекта) — это и есть «per-job sync». Подробности и сравнение с подходом «`uv sync` в `before_script` + кэш `.venv/`» — в [caching_and_uv.md](references/caching_and_uv.md).
- `UV_FROZEN=1` — `uv sync` падает, если `uv.lock` не соответствует `pyproject.toml` (lock не обновляется молча в CI).
- `UV_LINK_MODE=copy` — не ругаться на hardlink между кэшем и `.venv` на разных ФС раннера.
- Ключ кэша по `uv.lock` — кэш инвалидируется при смене зависимостей.

Джобы, которым `uv` не нужен (`build-image` на образе Kaniko, `container-scan` на образе Trivy), переопределяют `image:`, и им обязательно `before_script: []` и `cache: []`, чтобы сбросить `default`.

## workflow.rules

Чтобы не плодить два пайплайна (на push в ветку и на сам MR одновременно):

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS == null
    - if: $CI_COMMIT_TAG
```

(паттерн из `users/backend`; строку про теги добавь, если по тегам тоже нужны пайплайны)

## Джоба lint

Минимум — `ruff check` и `ruff format --check` по `src` (не по `.` — лишний шум на конфигах и кэшах). Плюс генерим Code Quality-отчёт для виджета в MR:

```yaml
ruff:
  stage: lint
  script:
    - uv sync --only-group lint --no-install-project
    - uv run ruff check src
    - uv run ruff check src --output-format=gitlab > gl-code-quality-report.json
  artifacts:
    when: always
    reports:
      codequality: gl-code-quality-report.json

ruff-format:
  stage: lint
  script:
    - uv sync --only-group lint --no-install-project
    - uv run ruff format --check src
```

Первый прогон `ruff check src` даёт читаемый вывод в лог и роняет джобу при ошибках; второй пишет машинный отчёт (он ничего не валит сам — гейтом служит первый прогон). Держать их разными джобами (`ruff` и `ruff-format`) — чтобы в UI было видно, что именно сломалось.

`bandit` (SAST) и `pip-audit` (зависимости) — тоже в стадии `lint`, как gate-джобы (падают на находках). Их конфигурация, форматы отчётов и tier-ограничения — в [reports_and_gates.md](references/reports_and_gates.md).

## Джобы test

Что запускать (какие директории — unit по слоям, integration по маркеру/директории), как устроен режим внешней инфраструктуры (`INTEGRATION_USE_EXTERNAL_INFRA=1`, переменные `INTEGRATION_*`) — берётся из `python-pytest-testing`. Здесь — CI-обвязка:

```yaml
unit-tests:
  stage: test
  script:
    - uv sync --no-default-groups --group test --no-install-project
    - >-
      uv run pytest src/tests/units
      --cov=src --cov-report=term-missing --cov-report=xml:coverage.xml --cov-report=html
      --junitxml=report.xml --durations=10 -q
  coverage: '/TOTAL.+?(\d+)%/'
  artifacts:
    when: always
    expire_in: 1 week
    paths:
      - htmlcov/
    reports:
      junit: report.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml

integration-tests:
  stage: test
  services:
    - name: postgres:18-alpine
      alias: postgres
      variables:
        POSTGRES_USER: <service>_test
        POSTGRES_DB: <service>_test
        POSTGRES_PASSWORD: <service>_test
    - name: nats:2.12-alpine
      alias: nats
      command: ["-js", "-m", "8222"]
  variables:
    INTEGRATION_USE_EXTERNAL_INFRA: "1"
    INTEGRATION_PG_HOST: postgres
    INTEGRATION_PG_PORT: "5432"
    INTEGRATION_PG_USER: <service>_test
    INTEGRATION_PG_DATABASE: <service>_test
    INTEGRATION_PG_PASSWORD: <service>_test
    INTEGRATION_NATS_HOST: nats
    INTEGRATION_NATS_PORT: "4222"
  script:
    - uv sync --no-default-groups --group test --no-install-project
    - >-
      uv run pytest src/tests/integration
      --cov=src --cov-report=term-missing --cov-report=xml:coverage.xml --junitxml=report.xml -q
  coverage: '/TOTAL.+?(\d+)%/'
  artifacts:
    when: always
    expire_in: 1 week
    reports:
      junit: report.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
```

- `--junitxml` + `reports:junit` → вкладка Tests в пайплайне и диф упавших тестов в MR (работает на GitLab CE).
- `--cov-report=xml:coverage.xml` + `reports:coverage_report` (cobertura) → подсветка покрытых строк в дифе MR (работает на CE).
- `coverage:`-regex вытаскивает процент в бейдж/виджет пайплайна.
- `--cov-report=html` + `paths: htmlcov/` → скачиваемый HTML-отчёт (опционально, но дёшево).
- `--durations=10` — топ-10 самых медленных тестов в логе.
- Порог покрытия (`--cov-fail-under`) **не** ставим по умолчанию — согласовано с `python-pytest-testing` (метрика-ориентир, не жёсткий гейт). Если команда хочет — добавляется в `pytest`-вызов, не в YAML.
- Если в проекте нет NATS — убери `nats` из `services:` и соответствующие переменные. Имена тестовых переменных подключения сверяй с тем, что реально читают фикстуры (`python-pytest-testing`).

## Джоба build-image

Сборка через **Kaniko** — без Docker-демона, без privileged-раннера, без монтирования docker-сокета в джобы. Почему Kaniko, а не docker-socket/dind, и что для этого нужно на стороне раннера/GitLab — в [build_and_registry.md](references/build_and_registry.md).

```yaml
build-image:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:debug
    entrypoint: [""]
  before_script: []
  cache: []
  variables:
    GIT_DEPTH: "1"
  script:
    - mkdir -p /kaniko/.docker
    - echo "{\"auths\":{\"${CI_REGISTRY}\":{\"username\":\"${CI_REGISTRY_USER}\",\"password\":\"${CI_REGISTRY_PASSWORD}\"}}}" > /kaniko/.docker/config.json
    - >-
      /kaniko/executor
      --context "${CI_PROJECT_DIR}"
      --dockerfile "${CI_PROJECT_DIR}/Dockerfile"
      ${KANIKO_REGISTRY_MIRROR:+--registry-mirror=$KANIKO_REGISTRY_MIRROR --insecure-pull}
      --destination "${CI_REGISTRY_IMAGE}:${IMAGE_TAG}"
      --destination "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHORT_SHA}"
  rules:
    - if: '$CI_COMMIT_BRANCH == "develop"'
      variables:
        IMAGE_TAG: dev
    - if: '$CI_COMMIT_BRANCH == "main"'
      variables:
        IMAGE_TAG: prod
```

- Тег по ветке задаётся через `variables:` внутри `rules:` — на любой другой ветке/в MR джоба не создаётся вообще.
- Дополнительный неизменяемый тег `$CI_COMMIT_SHORT_SHA` — чтобы откатываться на конкретный коммит и не гадать, что внутри `:dev`.
- `${KANIKO_REGISTRY_MIRROR:+...}` — если переменная (уровня группы/инстанса) задана, билд тянет базовые образы через pull-through кэш; если нет — напрямую. Имя сервиса кэша в репозиторий не зашиваем.
- `before_script: []` / `cache: []` — обязательны, иначе подтянется `default` с `pip install uv`.

## Джоба container-scan

Сканируем уже собранный образ Trivy'ем; gate на HIGH/CRITICAL. На GitLab CE виджета «N уязвимостей» в MR не будет (это Ultimate), но джоба роняет пайплайн и оставляет отчёт-артефакт. Конфигурация — в [reports_and_gates.md](references/reports_and_gates.md).

## Tier-замечание (GitLab CE)

На self-managed **CE** работают: вкладка Tests (JUnit), подсветка покрытия в дифе (cobertura), Code Quality-виджет. Security-репорты (`reports:sast`, `reports:dependency_scanning`, `reports:container_scanning`) с виджетами и Security Dashboard — это Ultimate; на CE соответствующие джобы (`bandit`, `pip-audit`, `container-scan`) всё равно полезны как **гейты** (падают на находках) и оставляют отчёт артефактом. В скиле security-джобы и сделаны так, чтобы ценность не зависела от тарифа.

## Definition of Done

- Стадии: `lint → test → build → scan`, имя — `lint` (не `check`).
- Есть `workflow.rules` — нет дублирующихся пайплайнов на branch+MR.
- `default:` несёт установку `uv` и кэш по `uv.lock`; джобы на чужих образах сбрасывают его (`before_script: []`, `cache: []`).
- `lint`: `ruff check src` + `ruff format --check src` + codequality-отчёт; `bandit` и `pip-audit` как гейты.
- `test`: `unit-tests` и `integration-tests` отдают `reports:junit` и `reports:coverage_report` (cobertura); запуск тестов соответствует `python-pytest-testing`; integration работает в режиме `INTEGRATION_USE_EXTERNAL_INFRA=1`.
- `build-image`: Kaniko; тег `dev` строго на `develop`, `prod` строго на `main`, плюс `$CI_COMMIT_SHORT_SHA`; на прочих ветках джобы нет; поддержан `KANIKO_REGISTRY_MIRROR`.
- `container-scan`: Trivy по собранному образу, gate на HIGH/CRITICAL.
- Нет дублирования настроек по джобам; `.yml` валиден (`python -c "import yaml; yaml.safe_load(open('.gitlab-ci.yml'))"` или CI Lint в GitLab).
- В описании учтено tier-ограничение CE для security-виджетов.
