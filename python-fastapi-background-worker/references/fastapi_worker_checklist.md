# FastAPI Worker Checklist

## Architecture

- Worker-логика отделена от FastAPI роутов.
- Worker использует application-layer use case, а не бизнес-логику в lifecycle callbacks.

## Runtime

- `uvloop` установлен и активирован до старта loop.
- Для неподдерживаемой платформы есть явный fallback и логирование.

## Lifecycle

- На startup создаются worker tasks.
- На shutdown новые задачи не принимаются.
- In-flight задачи корректно завершаются или отменяются по timeout.

## Reliability

- Есть retry-стратегия с лимитом попыток.
- Есть idempotency для задач с побочными эффектами.
- Конкурентность ограничена и измерима.

## Operations

- Метрики: queue depth, success/fail, retry, processing latency.
- Логи содержат task id, correlation id, attempt.
