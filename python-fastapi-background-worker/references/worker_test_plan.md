# Worker Test Plan

## Unit Tests

- Проверяй startup/shutdown переходы менеджера воркера.
- Проверяй классификацию ошибок и retry-политику.
- Проверяй idempotency поведения при повторной обработке.

## Integration Tests

- Проверяй, что worker стартует вместе с FastAPI lifecycle.
- Проверяй graceful shutdown с in-flight задачами.
- Проверяй метрики и логи по основным исходам (success/retry/fail).

## Scenario Matrix

1. Startup -> worker loop starts.
2. Task success -> commit/ack and metrics update.
3. Retriable error -> retry path triggered.
4. Terminal error -> fail path and observability.
5. Shutdown during in-flight -> bounded graceful stop.
