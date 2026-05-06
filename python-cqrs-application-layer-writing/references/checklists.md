# Checklists

Пошаговые чек-листы добавления типовых артефактов прикладного слоя.

## Добавление новой public-команды

1. Определи **цель** use case-а (существительное) и **action** (глагол).
2. Создай файл `application/commands/public/<aggregate>/<action>.py` (если директории `<aggregate>/` нет — создай вместе с `__init__.py`).
3. Определи команду:
   ```python
   @dataclass(slots=True, frozen=True)
   class <Verb><Aggregate>Command:
       initiator_id: UUID
       <aggregate>_id: UUID  # обязательно для команд, действующих над существующим агрегатом
       # ... другие поля примитивов
   ```
4. Определи use case, наследуй от `BaseUseCase`:
   ```python
   class <Verb><Aggregate>UseCase(BaseUseCase):
       async def execute(self, command: <Verb><Aggregate>Command) -> <Aggregate>SimpleDTO:
           ...
   ```
5. Тело `execute`:
   - Phase 1 (pre-transaction): `action = "..."` + конверсия примитивов в VO.
   - Phase 2: `async with self._uow as uow:`.
   - Phase 3: `initiator = await self._initiator(uow, initiator_id, action)` → `initiator.raise_admin()` (или нужная роль).
   - Phase 4: загрузка primary через `uow.<aggregate>_repositories.read.by_id(...)` → `AppNotFoundError` при `None`.
   - Phase 5: `<Aggregate>PolicyService().edit(initiator, [primary])`.
   - Phase 6: загрузка зависимостей (если есть) → `AppInvalidDataError` при `None`, validate-сервисы домена.
   - Phase 7: вызов мутатора агрегата.
   - Phase 8: `read.save(primary)` + `version.save(primary, <Aggregate>Event.<EVENT>, initiator.user_id)` + (опционально) `outbox.save(primary)`.
   - Phase 9: `return <Aggregate>SimpleDTO.from_domain(primary)`.
6. Обнови `application/commands/public/<aggregate>/__init__.py`: добавь re-export команды и use case-а в алфавитный `__all__`.
7. Если шаг 8 использует `outbox.save` — убедись, что `outbox: <Aggregate>OutboxRepository` присутствует в `<Aggregate>Repositories`.

## Добавление новой private-команды

1. Те же шаги, что для public, но:
   - Расположение: `application/commands/private/<aggregate>/<action>.py`.
   - Команда **без** `initiator_id` поля.
   - В `execute`: пропускаем Phase 3 (initiator) и Phase 5 (per-aggregate authorization).
   - При `version.save` `editor_id=None` (нет инициатора).
2. Обнови `application/commands/private/<aggregate>/__init__.py`.

## Добавление новой query

1. Определи: одиночный `Get` или list `List`; на текущей версии или версионный (`LastVersion` / `Version`).
2. Создай файл `application/queries/public/<aggregate>/<action>.py`. Имя файла:
   - `retrieve_last_version.py` — одиночный текущий.
   - `retrieve_version.py` — одиночный версионный.
   - `list_last_versions.py` — список текущих.
   - `list_versions.py` — список версионных.
3. Определи запрос:
   ```python
   @dataclass(slots=True, frozen=True)
   class Get<Aggregate>LastVersionQuery:
       initiator_id: UUID
       <aggregate>_id: UUID
   ```
   Для list — добавляются опциональные фильтры и `paginator: LimitOffsetPaginator`.
4. Определи use case, наследуй от `BaseUseCase` (из `queries/base.py`).
5. Тело `execute`:
   - Phase 1: `action` + конверсия (для list — конверсия идёт в `_filtering_data` ниже).
   - Phase 2: `async with self._uow as uow:` (для одиночного — один блок; для list-запроса с дополнительными подгрузками допустимо несколько последовательных).
   - Phase 3: `initiator = await self._initiator(...)` → `initiator.raise_reader()`.
   - Phase 4: для одиночного — `read.by_id(...)` → `AppNotFoundError`; для list — `read.filters(**self._filtering_data(query))`.
   - Phase 5: `<Aggregate>PolicyService().read(initiator, items)`.
   - Phase 6: `return <Aggregate>SimpleDTO.from_domain(...)` или `(list[DTO], int)` для list.
6. Если 3+ опциональных фильтра — добавь `_filtering_data(self, query) -> dict[str, Any]` приватный метод.
7. Обнови `application/queries/public/<aggregate>/__init__.py`.

## Добавление publisher use case

1. Убедись, что у агрегата есть `outbox: <Aggregate>OutboxRepository` в `<Aggregate>Repositories`.
2. Создай файл `application/commands/private/<aggregate>/publish.py`.
3. Определи use case, наследуй от `PublisherUseCase`:
   ```python
   class Publish<Aggregate>VersionsUseCase(PublisherUseCase):
       async def execute(self) -> None:
           async with self._uow as uow:
               versions = await uow.<aggregate>_repositories.outbox.not_published_versions()
               await self._event_publisher.batch_publish(versions)
               await uow.<aggregate>_repositories.outbox.batch_save(
                   [dto.<aggregate> for dto in versions]
               )
   ```
4. Обнови `__init__.py` агрегатной директории.
5. Убедись, что `<Aggregate>VersionDTO` присутствует в `Union PublishEventDTO` в `event_publisher.py`.

## Добавление портов нового агрегата

1. Создай `application/ports/repositories/<aggregate>.py`. Содержимое — подмножество следующего, в зависимости от роли агрегата:
   - `<Aggregate>ReadRepository` (наследует от `Domain<Aggregate>ReadRepository`) — обязательно.
   - `<Aggregate>Event` (`StrEnum` + `from_str`) — если есть version-репо.
   - `<Aggregate>VersionDTO` (`@dataclass`) — если есть version-репо.
   - `<Aggregate>VersionRepository` — если есть аудит-лог.
   - `<Aggregate>OutboxRepository` — если агрегат публикуется наружу.
   - `<Aggregate>SubscriptionRepository` — если агрегат подписан на события.
2. Обнови `application/ports/repositories/__init__.py`:
   - Импорты из нового файла.
   - Добавь все имена в алфавитный `__all__`.
   - Создай `<Aggregate>Repositories` (`@dataclass(slots=True)`) с полями, соответствующими определённым в шаге 1 интерфейсам.
3. Обнови `application/ports/unit_of_work.py`: добавь `@property @abstractmethod def <aggregate>_repositories(self) -> <Aggregate>Repositories: ...`.
4. Если агрегат публикуется наружу — обнови `Union PublishEventDTO` в `application/ports/event_publisher.py`.

## Добавление нового DTO

1. Определи: базовый (`Simple`) для одного агрегата или сценарный (композитный)?
2. Файл: `application/dto/<aggregate>.py` для агрегатных DTO; `application/dto/<scenario>.py` для кросс-агрегатных сценарных.
3. Определи DTO:
   ```python
   @dataclass(slots=True, frozen=True)
   class <Aggregate>SimpleDTO:
       <aggregate>_id: UUID
       # ... поля примитивов

       @classmethod
       def from_domain(cls, aggregate: <Aggregate>) -> Self:
           return cls(
               <aggregate>_id=aggregate.<aggregate>_id.<aggregate>_id,
               # ...
           )
   ```
4. Для версионного DTO — отдельный класс `<Aggregate>VersionSimpleDTO` с фабрикой `from_dto(cls, dto: <Aggregate>VersionDTO)`.
5. `application/dto/__init__.py` **остаётся пустым** — DTO импортируются напрямую из `application.dto.<aggregate>`.

## Добавление нового подкласса AppError

По умолчанию **не добавляем** — иерархия из четырёх классов (`AppError` + `AppNotFoundError` / `AppInvalidDataError` / `AppInternalError`) покрывает большинство случаев. Агрегат живёт в `data`, не в имени класса.

При обоснованной потребности (по согласованию с пользователем):
1. Реши, наследуется новый класс от `AppError` или от одного из подклассов.
2. Добавь определение в `application/errors.py`.
3. Зафиксируй, в каких use case-ах и для каких ситуаций он бросается — для последующего согласованного использования.
