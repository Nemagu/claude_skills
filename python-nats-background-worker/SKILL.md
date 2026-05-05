---
name: python-nats-background-worker
description: Используй при проектировании или реализации background worker на Python поверх NATS и JetStream. Триггеры — асинхронная обработка событий/команд, durable consumer, ack and retry, idempotency, DLQ, graceful shutdown, observability и обязательное использование uvloop как runtime event loop.
---

# Python NATS Background Worker

## Quick Start

1. Зафиксируй контракт сообщения: subject, schema, version, idempotency key.
2. Раздели transport handler и domain logic, чтобы бизнес-код не зависел от NATS-клиента.
3. Настрой consumer параметры: durable name, ack policy, ack wait, max deliver.
4. Включи `uvloop` как event loop policy до старта NATS клиента.
5. Определи стратегию обработки ошибок: retry, terminal-fail, DLQ.
6. Реализуй идемпотентность до запуска бизнес-операции.
7. Добавь метрики, structured logs и trace correlation.
8. Обеспечь graceful shutdown с корректным drain и остановкой in-flight задач.

## Runtime Requirement

- Всегда использовать `uvloop` для NATS-воркера, если платформа поддерживается.
- Инициализировать policy до подключения к NATS и запуска consumer loop.
- Шаблон инициализации: [uvloop_bootstrap.md](references/uvloop_bootstrap.md)

## Worker Lifecycle

### 1. Define Message Contract

- Поля минимум: `event_id`, `occurred_at`, `type`, `payload`, `version`.
- Версионируй схему сообщения и держи backward compatibility.
- Проверяй payload до входа в domain use case.

### 2. Build Consumer Topology

- Выбирай `durable consumer` для гарантированной обработки после рестарта.
- Разделяй subjects по bounded context, избегай перегруженных wildcard-подписок.
- Задавай explicit naming для stream, consumer и queue group.

### 3. Implement Handler Pipeline

- Делай pipeline: decode -> validate -> deduplicate -> handle -> ack.
- При временной ошибке используй retry-политику.
- При невалидных или терминальных ошибках отправляй в DLQ или фиксируй terminal outcome.
- Паттерн пайплайна смотри: [handler_pipeline_template.md](references/handler_pipeline_template.md)

### 4. Configure Retry and DLQ

- Ограничивай количество повторов через `max_deliver`.
- Разделяй retriable и non-retriable исключения.
- Логируй причину последней неудачи и счетчик попыток.
- Шаблон классификации ошибок смотри: [retry_and_dlq_strategy.md](references/retry_and_dlq_strategy.md)

### 5. Add Observability

- Метрики минимум: `received_total`, `success_total`, `failed_total`, `retry_total`, `processing_latency`.
- В логах добавляй `event_id`, `subject`, `consumer`, `attempt`.
- Прокидывай correlation id между сообщениями и downstream вызовами.

### 6. Ensure Graceful Shutdown

- Останавливай intake новых сообщений перед завершением.
- Дожидайся in-flight задач с ограниченным timeout.
- Используй drain или эквивалентный механизм клиента.

## Anti-Patterns

- Бизнес-логика внутри callback без выделенного application-layer use case.
- Ack до завершения бизнес-операции.
- Бесконечные retry без лимита и без DLQ.
- Отсутствие идемпотентности при повторной доставке.
- Отсутствие `uvloop` policy в runtime настройке воркера.
- Глобальный broad subject, смешивающий несвязанные события.

## Definition of Done

- Контракт сообщения формализован и валидируется.
- Consumer устойчив к рестартам и повторной доставке.
- `uvloop` подключен и инициализируется до старта NATS клиента.
- Retry-поведение ограничено и предсказуемо.
- Терминальные ошибки маршрутизируются в DLQ или эквивалентный канал.
- Идемпотентность реализована и покрыта тестами.
- Есть метрики, структурные логи и сценарий graceful shutdown.

## References

- Чеклист проектирования воркера: [worker_design_checklist.md](references/worker_design_checklist.md)
- Шаблон обработчика: [handler_pipeline_template.md](references/handler_pipeline_template.md)
- Стратегия retry и DLQ: [retry_and_dlq_strategy.md](references/retry_and_dlq_strategy.md)
- Инициализация uvloop: [uvloop_bootstrap.md](references/uvloop_bootstrap.md)
- Тестирование воркера: [worker_testing_strategy.md](references/worker_testing_strategy.md)
