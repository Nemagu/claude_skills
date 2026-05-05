---
name: python-pytest-testing
description: Используй при проектировании, написании или проверке автотестов на Python через pytest и pytest-cov. Триггеры — добавление/правка unit и integration тестов, организация фикстур и фабрик, параметризация через pytest.mark.parametrize, улучшение структуры тестов и стабильный запуск через единый guard-скрипт.
---

# Python Pytest Testing

## Quick Start

1. Определи тип проверки: unit, integration или смешанный сценарий.
2. Сформируй список проверяемых контрактов и инвариантов до написания кода тестов.
3. Выбери структуру фикстур и фабрик; исключи дублирование через общий `conftest.py` на минимально подходящем уровне.
4. Напиши тесты с явными входными данными и наблюдаемым результатом.
5. Объедини схожие кейсы через `pytest.mark.parametrize` и добавь `ids`.
6. Запусти preflight и тесты через `scripts/run_pytest_guard.sh`.
7. Удали неиспользуемые фикстуры, стабилизируй flaky-поведение, зафиксируй итоговый DoD.

## Runner Modes (v2.1)

Скрипт: `scripts/run_pytest_guard.sh`

- `quick`: быстрый прогон для итерации.
- `full`: полный прогон выбранного target.
- `cov`: прогон с покрытием `pytest-cov`.
- `changed`: прогон только затронутых тестов на основе `git diff`.

Примеры:

```bash
scripts/run_pytest_guard.sh quick src/tests/unit
scripts/run_pytest_guard.sh full
scripts/run_pytest_guard.sh cov src/tests -- -k "not slow"
scripts/run_pytest_guard.sh changed
CHANGED_BASE=origin/main scripts/run_pytest_guard.sh changed
CHANGED_FALLBACK=none scripts/run_pytest_guard.sh changed
```

Поведение guard-скрипта:

- Использует `uv run pytest`, если `uv` доступен, иначе прямой `pytest`.
- Проверяет наличие `tests/` или `src/tests/`.
- Валидирует существование target.
- В `cov`-режиме проверяет доступность `pytest-cov`.
- В `changed`-режиме собирает изменения из staged/unstaged/untracked файлов.
- Поддерживает `COV_TARGET` (по умолчанию `src`), `CHANGED_BASE`, `CHANGED_INCLUDE_UNTRACKED`, `CHANGED_FALLBACK`.

## Workflow

### 1. Classify Test Scope

- Помечай тест как `unit`, если внешние зависимости заменены doubles/fakes и проверяется локальный контракт.
- Помечай тест как `integration`, если проверяется связка модулей или реальная инфраструктура.
- Не смешивай в одном тесте unit и integration цели.

### 2. Design Cases Before Implementation

- Определи минимум: happy path, граничные условия, невалидные входы, отказоустойчивость.
- Формулируй поведение через контракт: вход, действие, ожидаемый эффект.
- Для багфикса сначала добавляй воспроизводящий тест, затем исправляй код.

### 3. Build Fixtures and Factories

- Держи фикстуры узкими по ответственности.
- Выноси общие фикстуры в `conftest.py` только при реальном переиспользовании.
- Создавай фабрики для агрегатов/команд/DTO, чтобы тест не зависел от лишних полей.
- Смотри decision tree: [fixture_and_factory_patterns.md](references/fixture_and_factory_patterns.md).

### 4. Parameterize Similar Scenarios

- Используй `pytest.mark.parametrize` для повторяемых сценариев с одинаковой структурой шагов.
- Всегда задавай `ids`, чтобы названия тестов отражали смысл кейса.
- Пример паттерна смотри в [pytest_best_practices.md](references/pytest_best_practices.md).

### 5. Validate and Harden

- На итерации используй `quick` или `changed`.
- Перед завершением запускай `full` и `cov`.
- Проверяй стабильность: тест не должен зависеть от порядка запуска и времени выполнения.

## Definition of Done

- Есть тесты на ключевые контракты и регрессионные риски.
- Схожие сценарии параметризованы и читаемы по `ids`.
- Фикстуры и фабрики не дублируются между модулями.
- Интеграционные тесты явно отделены от unit-тестов.
- Тестовый набор проходит локально; метрики покрытия соответствуют целям команды.

## References

- Практики и анти-паттерны: [pytest_best_practices.md](references/pytest_best_practices.md)
- Стратегия покрытия: [coverage_strategy.md](references/coverage_strategy.md)
- Decision tree для фикстур и фабрик: [fixture_and_factory_patterns.md](references/fixture_and_factory_patterns.md)
- Конфиг-файлы и инфраструктура в тестах: [config_and_infrastructure.md](references/config_and_infrastructure.md)
