# Coverage Strategy

## Цель покрытия

- Используй покрытие как индикатор непроверенных рисков, а не как самоцель.
- Повышай покрытие в первую очередь в критичном домене и местах прошлых дефектов.

## Приоритизация

1. Доменные инварианты и правила.
2. Прикладные сценарии с ветвлениями и обработкой ошибок.
3. Инфраструктурные адаптеры с контрактными тестами.

## Минимальный цикл проверки

```bash
scripts/run_pytest_guard.sh changed
scripts/run_pytest_guard.sh full
scripts/run_pytest_guard.sh cov
```

## Настройка changed-режима

```bash
CHANGED_BASE=origin/main scripts/run_pytest_guard.sh changed
CHANGED_INCLUDE_UNTRACKED=0 scripts/run_pytest_guard.sh changed
CHANGED_FALLBACK=none scripts/run_pytest_guard.sh changed
```

## Альтернативный запуск без guard-скрипта

```bash
pytest -q
pytest --cov=src --cov-report=term-missing
```

## Интерпретация отчета

- Смотри на строки и ветки, которые не покрыты в высокорисковых модулях.
- Если покрытие низкое из-за мертвого или транзитного кода, зафиксируй решение: удалить код или добавить тесты.
- Не добавляй искусственные тесты без бизнес-ценности только ради процентов.
