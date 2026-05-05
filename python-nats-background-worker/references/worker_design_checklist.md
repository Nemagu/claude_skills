# Worker Design Checklist

## Contract

- У сообщения есть schema version и стабильные обязательные поля.
- Есть idempotency key или эквивалентный dedup ключ.
- Контракт документирован и проверяется на входе.

## Topology

- Выбран корректный stream и subject namespace.
- Настроен durable consumer.
- Выбрана модель конкуренции: single consumer или queue group.

## Reliability

- Ack выполняется только после успешной обработки.
- Есть лимит повторов и политика terminal-fail.
- Настроен DLQ или fallback-канал для неуспешных сообщений.

## State and Idempotency

- Повторное сообщение не приводит к повторному side effect.
- Dedup storage согласован с TTL и retention сообщении.
- Внешние вызовы защищены от повторного выполнения.

## Operations

- Есть метрики throughput, error-rate и latency.
- Логи содержат идентификаторы трассировки.
- Graceful shutdown закрывает воркер без потери подтвержденных результатов.
