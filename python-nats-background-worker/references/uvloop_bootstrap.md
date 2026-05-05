# uvloop Bootstrap for NATS Worker

## Recommended Bootstrap

```python
import asyncio
import uvloop


def configure_event_loop() -> None:
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
```

- Вызывай `configure_event_loop()` в entrypoint до подключения к NATS.
- Не меняй event loop policy после запуска consumer tasks.

## Fallback Guidance

- Если платформа не поддерживает `uvloop`, логируй явный fallback.
- Fallback не должен быть silent, чтобы не терять контроль над latency профилем.
