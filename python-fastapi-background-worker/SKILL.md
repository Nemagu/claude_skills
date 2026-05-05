---
name: python-fastapi-background-worker
description: Используй при проектировании или реализации background worker в Python-приложении на FastAPI. Триггеры — фоновые задачи через lifecycle startup/shutdown, очереди, конкурентность, retry/idempotency, observability и обязательное использование uvloop как runtime event loop.
---

# Python FastAPI Background Worker

## Quick Start

1. Раздели HTTP слой и worker pipeline: воркер не должен зависеть от маршрутов.
2. Определи источник задач: внутренняя очередь, периодический планировщик или внешний брокер.
3. Привяжи запуск и остановку воркера к lifecycle FastAPI (`startup`/`shutdown` или lifespan).
4. Включи `uvloop` как event loop policy до старта приложения.
5. Добавь ограничения конкуренции, таймауты и правила retry.
6. Реализуй idempotency для задач с side effects.
7. Добавь метрики, structured logs и graceful shutdown.

## Runtime Requirement

- Всегда использовать `uvloop` для воркеров в production и локальной разработке, если платформа поддерживается.
- Инициализировать `uvloop` до создания/запуска event loop.
- Шаблон инициализации смотри: [uvloop_bootstrap.md](references/uvloop_bootstrap.md)

## Worker Lifecycle

### 1. Startup

- Создай worker manager на старте приложения.
- Подними фоновую задачу через `asyncio.create_task`.
- Сохрани handle задачи и shared cancel token.

### 2. Processing Loop

- Построй цикл: poll -> validate -> execute -> commit/ack -> metrics.
- Раздели retriable и terminal ошибки.
- Не допускай бесконечный retry без лимита.

### 3. Shutdown

- Останови intake новых задач.
- Дождись завершения in-flight задач с timeout.
- Отмени зависшие задачи, корректно обработай `CancelledError`.

## Reliability Patterns

- Используй bounded queue и backpressure.
- Ограничивай конкурентность через semaphore/worker pool.
- Добавляй jitter/backoff для retry.
- Фиксируй idempotency key до повторного выполнения внешнего side effect.

## Anti-Patterns

- Запуск background цикла без контроля lifecycle.
- Отсутствие `uvloop` policy при заявленной высокой нагрузке.
- Неконтролируемое число параллельных задач.
- Ack/commit до завершения бизнес-операции.
- Silent-exception в фоне без метрик и логов.

## Definition of Done

- Worker запускается и останавливается через lifecycle FastAPI.
- `uvloop` подключен и инициализируется в правильной точке старта.
- Ошибки классифицированы на retriable и terminal.
- Есть лимиты конкуренции и защита от переполнения очереди.
- Идемпотентность и retry-поведение покрыты тестами.
- Добавлены метрики, структурные логи и shutdown-сценарии.

## References

- Чеклист воркера: [fastapi_worker_checklist.md](references/fastapi_worker_checklist.md)
- Шаблон lifecycle-менеджера: [worker_lifecycle_template.md](references/worker_lifecycle_template.md)
- Инициализация uvloop: [uvloop_bootstrap.md](references/uvloop_bootstrap.md)
- Тестирование воркера: [worker_test_plan.md](references/worker_test_plan.md)
