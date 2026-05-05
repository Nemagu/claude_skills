# Worker Testing Strategy

## Unit Tests

- Проверяй классификацию ошибок: retriable и terminal.
- Проверяй порядок действий pipeline: validate, dedup, handle, ack/nak.
- Проверяй, что duplicate события не запускают side effect повторно.

## Integration Tests

- Поднимай NATS окружение в тестах автоматически.
- Проверяй retry-поведение и переход в DLQ.
- Проверяй graceful shutdown при in-flight обработке.

## Test Cases Matrix

1. Valid event -> use case success -> ack.
2. Duplicate event -> skip use case -> ack.
3. Retriable failure -> nak/retry.
4. Terminal failure -> DLQ publish -> ack.
5. Max retry reached -> terminal outcome observable.
