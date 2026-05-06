# Use Cases

## Допущения раздела

- Раздел опирается на существующий domain-слой (агрегаты, VO, доменные сервисы) и принятый в проекте паттерн `UnitOfWork`.
- Конкретные имена базовых классов, имена доменных VO и сервисов в примерах — **иллюстрация**. Универсальна только структура.
- Если в проекте нет домена / нет базовых классов / нет UoW-паттерна — это **гейт**: до согласования с пользователем не вводим эти абстракции сами.

## Базовые классы — пример конвенции

В CQRS-сценариях типично выделяют один-два базовых класса для use case-ов: общие зависимости (UoW, event publisher) и helper-ы (загрузка инициатора) собираются туда, конкретные use case-ы переопределяют только `execute`.

**Пример минимального набора:**

```python
# application/commands/base.py
from abc import ABC

from application.errors import AppInvalidDataError
from application.ports.event_publisher import EventPublisher
from application.ports.unit_of_work import UnitOfWork
from domain.user import User, UserID


class BaseUseCase(ABC):
    def __init__(self, uow: UnitOfWork) -> None:
        self._uow = uow

    async def _initiator(
        self, uow: UnitOfWork, initiator_id: UserID, action: str
    ) -> User:
        initiator = await uow.user_repositories.read.by_id(initiator_id)
        if initiator is None:
            raise AppInvalidDataError(
                msg="инициатор не существует",
                action=action,
                data={"user": {"user_id": initiator_id.user_id}},
            )
        return initiator


class PublisherUseCase(BaseUseCase):
    def __init__(self, uow: UnitOfWork, event_publisher: EventPublisher) -> None:
        super().__init__(uow)
        self._event_publisher = event_publisher
```

```python
# application/queries/base.py — точная копия BaseUseCase, без PublisherUseCase
class BaseUseCase(ABC):
    def __init__(self, uow: UnitOfWork) -> None:
        self._uow = uow

    async def _initiator(
        self, uow: UnitOfWork, initiator_id: UserID, action: str
    ) -> User:
        ...  # та же реализация
```

**Альтернативные варианты:**
- Базовых классов нет вовсе — каждый use case принимает зависимости через свой `__init__`.
- Один базовый класс на всё.
- Много базовых — на каждую категорию (отдельно для public/private/publisher и т.п.).

Скил предписывает **принцип**: общие зависимости и helper-ы выносятся в базовые классы; конкретный набор — конвенция конкретного проекта. Если базовых классов в проекте ещё нет — согласуй с пользователем, какой минимум нужно ввести.

## Конструктор use case

Use case **не определяет свой `__init__`** — наследует от базового класса, в котором уже принимаются нужные зависимости. Никаких дополнительных параметров.

```python
class UpdateTenantUseCase(BaseUseCase):
    async def execute(self, command: UpdateTenantCommand) -> TenantSimpleDTO:
        ...
```

Если у проекта нет базовых классов — конструктор принимает зависимости напрямую (`UnitOfWork`, при необходимости `EventPublisher`), но всё равно use case содержит только `async def execute(...)` как публичный метод.

## Шаблон `execute` — универсальные пункты и точки согласования

### Универсально (без согласования)

- Сигнатура `async def execute(self, command_or_query) -> ...` (или `async def execute(self) -> ...` для use case без входа).
- Тип возврата — DTO либо `tuple[list[DTO], int]` для list-запросов; никакой утечки domain-объектов.
- **Пред-транзакционная фаза** — все операции, которые могут бросить исключение и не требуют доступа к БД, выполняются **до** открытия транзакции:
  - конверсия примитивов команды/запроса в VO (конструктор VO, `StrEnum.from_str`);
  - синхронная валидация формата/диапазона значений, не зависящая от состояния БД;
  - вычисление производных значений из входа.
- **Границы транзакций** (при наличии UoW):
  - **Команда** (мутация): один `async with self._uow as uow:` блок на весь `execute`. Атомарность мутаций критична.
  - **Запрос** (чтение): допустимо несколько последовательных `async with` блоков, чтобы не удерживать соединение/блокировки БД дольше необходимого.
  - В обоих случаях запрещены **вложенные** блоки.
- Все обращения к репозиториям — через локальный `uow`, не через `self._uow`. Внутри блока: `uow.<aggregate>_repositories.read.<method>(...)`.
- Helper-методы, трогающие репозитории (`_initiator`, `_filtering_data`, любой пользовательский), **принимают `uow` параметром** — `__aenter__` UoW может вернуть транзакционно-связанный объект, отличный от `self._uow`.

### Согласовать с пользователем (опираясь на domain-слой)

- Нужна ли авторизация инициатора и в какой форме (есть ли в домене аналог `User` / role-check).
- Нужен ли per-aggregate policy-check и через какой сервис домена.
- Какие агрегаты загружаются и в каком порядке; что считается primary, что — зависимостью.
- Какие validate-сервисы домена применяются и где в потоке.
- Какие мутаторы агрегата вызываются.
- Какие репозиторные операции выполняются на запись (`read.save`, `version.save`, `outbox.save`) — определяется наличием соответствующих полей в `<Aggregate>Repositories`.
- Какой DTO возвращается и через какую фабрику (`from_domain` / `from_dto`).

### Референс-пример (типовой паттерн)

Шаблон, который в большинстве проектов работает как отправная точка для public command. **Не предписание**, а основа для согласования.

```python
async def execute(self, command: UpdateTenantCommand) -> TenantSimpleDTO:
    # ── Phase 1: pre-transaction setup ────────────────────────
    action = "обновление арендатора"
    initiator_id = UserID(command.initiator_id)
    tenant_id = TenantID(command.tenant_id)
    new_status = TenantStatus.from_str(command.status)
    # ──────────────────────────────────────────────────────────
    async with self._uow as uow:
        # ── Phase 2: initiator + role (public only) ───────────
        initiator = await self._initiator(uow, initiator_id, action)
        initiator.raise_admin()

        # ── Phase 3: load primary ─────────────────────────────
        tenant = await uow.tenant_repositories.read.by_id(tenant_id)
        if tenant is None:
            raise AppNotFoundError(
                msg="арендатор не существует",
                action=action,
                data={"tenant": {"tenant_id": tenant_id.tenant_id}},
            )

        # ── Phase 4: per-aggregate authorization ──────────────
        TenantPolicyService().edit(initiator, [tenant])

        # ── Phase 5: domain mutation ──────────────────────────
        tenant.new_status(new_status)

        # ── Phase 6: save ─────────────────────────────────────
        await uow.tenant_repositories.read.save(tenant)
        await uow.tenant_repositories.version.save(
            tenant, TenantEvent.UPDATED, initiator.user_id
        )

        # ── Phase 7: return DTO ───────────────────────────────
        return TenantSimpleDTO.from_domain(tenant)
```

### Применимость фаз по типу use case

| Фаза | public command | private command | public query |
|---|:-:|:-:|:-:|
| 1. action + VO + pre-transaction | ✓ | ✓ | ✓ |
| 2. initiator + role | ✓ (`raise_admin`) | — | ✓ (`raise_reader`) |
| 3. load primary | ✓ | ✓ | ✓ |
| 4. per-aggregate authorization | ✓ (`.edit`) | — | ✓ (`.read`) |
| 5. domain mutation | ✓ | ✓ | — |
| 6. save | ✓ | ✓ (если есть в `<Aggregate>Repositories`) | — |
| 7. return | DTO | DTO или `None` | DTO или `(list[DTO], int)` |

## Initiator

Условия применения:
- **Public use case (command/query)** — обязательный шаг сразу после открытия UoW.
- **Private use case** — отсутствует. Initiator не передаётся в команду.
- **Publisher use case** (subtype private) — отсутствует.

Использование:

```python
initiator = await self._initiator(uow, UserID(command.initiator_id), action)
initiator.raise_admin()   # для команд: требуется роль admin
# или
initiator.raise_reader()  # для запросов: достаточно reader
```

Внутри `_initiator`:
- Загрузка `User` (или эквивалентного агрегата-инициатора) из `uow.<user>_repositories.read.by_id(...)`.
- Если `None` — `AppInvalidDataError` (initiator всегда `InvalidData`, не `NotFound`).
- `uow` параметром обязателен — внутри `__aenter__` UoW может вернуть транзакционно-связанный объект, отличный от `self._uow`.

Порядок: `_initiator` → `raise_<role>` → загрузка остальных агрегатов. Обратный порядок (сначала загрузка primary, потом проверка роли) недопустим — нельзя делать I/O от лица неавторизованного инициатора.

## Per-aggregate authorization (PolicyService)

Что это: доменный сервис из `domain/<aggregate>/services.py`, проверяет, имеет ли инициатор право выполнять конкретное действие над конкретным набором агрегатов.

Различие с `raise_admin/reader`:
- `initiator.raise_admin()` — глобальная роль («может что-то менять вообще»).
- `<Aggregate>PolicyService().edit(initiator, [primary])` — право над *этим* объектом (например, только в своём tenant).

Где в шаблоне: **сразу после загрузки соответствующего агрегата, до мутации**. Для list-запроса — после получения списка, над всеми элементами разом: `policy.read(initiator, items)`.

Применимость:
- public command → `.edit(initiator, [primary])`.
- public query → `.read(initiator, items)`.
- private — отсутствует.

Если в домене такого сервиса нет — согласуй с пользователем форму авторизации.

## Транзакционные границы (UoW)

### Когда UoW нужен

- Use case делает **несколько write-операций**, требующих атомарности.
- Use case обращается к **нескольким репозиториям** — вместо инжекции N репозиториев через `__init__` инжектируется один UoW.

### Когда без него

- Use case трогает один репозиторий, write-операция атомарна сама по себе.
- Read-only use case с одним источником.

UoW как универсальный паттерн — рекомендация по умолчанию, но осмысленные исключения возможны (это design decision, не догма).

### Правила границ блока

При наличии UoW:
- Один `execute` команды = **один** `async with self._uow as uow:` блок (атомарность мутаций).
- Запрос — допустимо **несколько последовательных** блоков (чтобы не держать ресурсы БД).
- Запрещены **вложенные** блоки.
- Все обращения к репозиториям — через локальный `uow`, не через `self._uow`.
- Helper-методы, работающие с репо, принимают `uow` параметром.
- `uow` не сохраняется в state объекта (валиден только в пределах своего блока).

## Обработка ошибок

### Универсально (без согласования)

Use case **не ловит** ошибки своего слоя (`AppError` и потомки). Прикладные исключения — намеренный control flow слоя приложения.

### Согласовать с пользователем

- **Доменные исключения**: по умолчанию пробрасываются как есть. Локально use case **может ловить** конкретную доменную ошибку, чтобы перевести её в более конкретную прикладную с дополнительным контекстом — это согласованное исключение, не норма.
- **Технические исключения** (БД, брокер): по умолчанию ловятся в infrastructure-адаптерах и оборачиваются в `AppInternalError`. Если проект требует иначе — согласовать.
- Какие именно типы из иерархии `AppError` применяются в данном use case (минимум — `AppNotFoundError` / `AppInvalidDataError`).

Логирование внутри use case **не делается** — это не уровень application.

### Anti-patterns

- `try/except AppError:` в use case.
- `try/except Exception:` оборачивание тех. исключений в use case (это уровень infrastructure).
- Логирование ошибок в use case.
- Catch-and-ignore доменных ошибок.
