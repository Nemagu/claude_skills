# uvloop Bootstrap

## Recommended Bootstrap

```python
import asyncio
import uvloop


def configure_event_loop() -> None:
    asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
```

- Вызывай `configure_event_loop()` в entrypoint до создания FastAPI app или запуска worker.
- Не меняй policy в середине жизненного цикла процесса.

## Fallback Guidance

- Если целевая платформа не поддерживает `uvloop`, логируй fallback на стандартный loop.
- Fallback должен быть явным и наблюдаемым, не silent.
