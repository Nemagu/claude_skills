# Worker Lifecycle Template

```python
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI


class WorkerManager:
    def __init__(self) -> None:
        self._task: asyncio.Task | None = None
        self._stop = asyncio.Event()

    async def start(self) -> None:
        self._task = asyncio.create_task(self._run())

    async def stop(self) -> None:
        self._stop.set()
        if self._task is not None:
            await asyncio.wait_for(self._task, timeout=10)

    async def _run(self) -> None:
        while not self._stop.is_set():
            await process_one_iteration()


worker = WorkerManager()


@asynccontextmanager
async def lifespan(_: FastAPI):
    await worker.start()
    try:
        yield
    finally:
        await worker.stop()


app = FastAPI(lifespan=lifespan)
```

## Notes

- Не держи тяжелую бизнес-логику внутри lifecycle функции.
- Управляй timeout на shutdown явно.
- Отдельно обработай `CancelledError` в внутренних задачах.
