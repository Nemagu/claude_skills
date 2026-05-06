# Outbox Pattern & Publisher Use Case

## Зачем нужен

Publisher use case — **раздельный шаг публикации** доменных событий наружу. Команда-мутатор пишет состояние и outbox-запись **в одной транзакции**, а отдельный publisher use case читает накопленные outbox-записи и шлёт их через `EventPublisher` в брокер.

Цель — гарантировать атомарность «состояние БД ↔ исходящее событие» без распределённой транзакции БД ↔ брокер. Стандартный transactional outbox pattern.

## Когда нужен

- Только для агрегатов, у которых в `<Aggregate>Repositories` присутствует **`outbox: <Aggregate>OutboxRepository`** (т.е. агрегат публикуется наружу).
- На каждый такой агрегат — один publisher use case.

## Расположение и форма

| Атрибут | Значение |
|---|---|
| Файл | `commands/private/<aggregate>/publish.py` |
| Базовый класс | `PublisherUseCase` (или эквивалент в проекте) |
| Имя класса | `Publish<Aggregate>VersionsUseCase` |
| Команда на вход | **нет** — `execute(self) -> None` без аргументов |
| Initiator / авторизация | отсутствуют (private) |
| Возврат | `None` |

## Шаблон `execute`

```python
from application.commands.base import PublisherUseCase


class PublishTenantVersionsUseCase(PublisherUseCase):
    async def execute(self) -> None:
        async with self._uow as uow:
            versions = await uow.tenant_repositories.outbox.not_published_versions()
            await self._event_publisher.batch_publish(versions)
            await uow.tenant_repositories.outbox.batch_save(
                [dto.tenant for dto in versions]
            )
```

Три шага в строгом порядке:
1. **Read.** `outbox.not_published_versions()` → `list[<Aggregate>VersionDTO]` (port-level VersionDTO).
2. **Publish.** `event_publisher.batch_publish(versions)` — массовая публикация в брокер.
3. **Mark.** `outbox.batch_save([dto.<aggregate> for dto in versions])` — отмечает агрегаты как опубликованные.

Один `async with self._uow` на всё — атомарность read+mark в одной транзакции.

## Различия с обычной командой

| Аспект | Обычная команда | Publisher use case |
|---|---|---|
| Команда-аргумент | да (`@dataclass`) | нет |
| Initiator + role | да (public) / нет (private) | нет |
| Per-aggregate authorization | да (public) / нет (private) | нет |
| Доменные мутаторы | да | нет |
| `read.save` / `version.save` | да | нет |
| `outbox.save` | опционально | основное действие (`batch_save` с маркировкой) |
| `event_publisher.batch_publish` | нет | да, обязательное |

Publisher use case **ничего не мутирует в домене**, не вызывает доменных сервисов и не работает с авторизацией. Это инфраструктурный медиатор поверх UoW.

## Запрет: публикация прямо из обычной команды

```python
# ✗ нарушение паттерна
class UpdateTenantUseCase(BaseUseCase):
    async def execute(self, command: UpdateTenantCommand) -> TenantSimpleDTO:
        async with self._uow as uow:
            ...
            await uow.tenant_repositories.read.save(tenant)
            await uow.tenant_repositories.version.save(...)
            await self._event_publisher.publish(...)  # ✗
            return ...
```

Почему запрещено:
- Брокер не участвует в транзакции БД. Если publish прошёл, а коммит БД упал — слетела согласованность.
- Если publish упал, а БД закоммитилась — событие потеряно.
- Outbox-паттерн решает это разнесением во времени: БД-запись (включая outbox) атомарна, публикация — отдельно через retry-friendly publisher use case.

Команда **только пишет в outbox** через свой `outbox.save(...)` (если у агрегата есть outbox). Публикацию делает publisher use case.

## Кто вызывает publisher use case

**За рамками application-слоя.** Обычно — фоновый worker / scheduler из `presentation/`, который дёргает publisher use case на интервале или по триггеру. Application-скил это не описывает.

Идемпотентность и повторная публикация (если publisher упал между шагами 2 и 3) — задача consumer-а событий (тот должен обрабатывать дубликаты), не publisher use case.

## Anti-patterns

- Команда на вход publisher use case — никогда. Лимиты — задача `not_published_versions`; фильтры — отдельный use case при появлении реальной потребности.
- Одиночная публикация (`publish` в цикле) вместо `batch_publish` — `EventPublisher` обязан иметь `batch_publish`, `OutboxRepository` — `batch_save` + `not_published_versions`.
- Несколько `async with self._uow` блоков в publisher use case — атомарность read+mark критична.
- Publisher use case для агрегата без `outbox`-поля в `<Aggregate>Repositories` — выдумывание возможностей слоя.
