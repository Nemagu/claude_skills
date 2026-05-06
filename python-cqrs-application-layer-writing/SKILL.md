---
name: python-cqrs-application-layer-writing
description: Используй при проектировании или правке прикладного слоя в Python-проекте по гексагональной архитектуре с CQRS. Триггеры — добавление или изменение use case (команды/запроса), DTO, портов (UnitOfWork, EventPublisher, repository interfaces), иерархии прикладных ошибок в `application/`. Не применять для слоёв `domain/`, `infrastructure/`, `presentation/`.
---

# Python CQRS Application Layer Writing

## Quick Start

1. Определи тип use case: команда (мутирует состояние, возвращает DTO или `None`) или запрос (только чтение, возвращает DTO либо `tuple[list[DTO], int]`).
2. Определи аудиторию: public (вызывается пользователем, требует initiator + проверку роли) или private (системный/событийный, без initiator).
3. Расположи файл: `application/commands/{public,private}/<aggregate>/<action>.py` или `application/queries/public/<aggregate>/<action>.py`. Один use case = один файл, имя файла = action в snake_case (`create.py`, `update.py`, `delete.py`, `restore.py`, `publish.py`, `retrieve_last_version.py`).
4. Выбери базовый класс по конвенции проекта: общий для use case-ов с UoW и опциональный — для use case-ов с публикацией событий из outbox. Если базовых классов в проекте нет — согласуй с пользователем.
5. Объяви команду/запрос как `@dataclass(slots=True, frozen=True)` с примитивами (`UUID`, `int`, `str`, `list[...] | None`). Доменные VO в команды/запросы не помещаем.
6. Тело `execute` начинается с `action: str` (русское описание для контекста ошибок), затем конверсия примитивов в VO (всё, что может упасть и не требует БД — до открытия транзакции), затем `async with self._uow as uow:`.
7. В public use case первым делом: получить инициатора и проверить его роль. Helper-методы, работающие с репозиториями, принимают `uow` параметром (`__aenter__` UoW может вернуть транзакционно-связанный объект, отличный от `self._uow`).
8. Загружай агрегаты через `uow.<x>_repositories.read.by_id(...)`. На `None` бросай `AppNotFoundError` (для основного ресурса операции — цели) или `AppInvalidDataError` (для зависимости/контекста). Initiator — всегда `AppInvalidDataError`.
9. Авторизуй конкретные агрегаты через доменный per-aggregate сервис (если есть в домене). Это дополняет глобальную проверку роли инициатора, проверяя право над *этими* объектами.
10. Вызови мутатор агрегата (для query — пропусти), затем сохрани через `read.save` + (опционально) `version.save` + (опционально) `outbox.save`. Состав репозиториев агрегата фиксирован в `<Aggregate>Repositories`.
11. Верни DTO (`from_domain` / `from_dto`-фабрика) или `tuple[list[DTO], int]` для list-запросов. Сборку фильтра в list-запросе выноси в приватный `_filtering_data(query) -> dict[str, Any]`.
12. Запрещено: f-строки в `msg=` ошибок, бизнес-логика в `execute` (должна быть в domain), импорты из `infrastructure/` или `presentation/`, доменные типы в полях команд/запросов и в return type, обращения к репозиторию вне `async with self._uow`.

## When to Apply

### Триггеры активации

**По расположению файлов** — любая правка/создание в `application/`:
- `application/commands/{public,private}/<aggregate>/<action>.py`
- `application/queries/public/<aggregate>/<action>.py`
- `application/commands/base.py`, `application/queries/base.py`
- `application/dto/<aggregate>.py`, `application/dto/paginators.py`
- `application/ports/unit_of_work.py`, `application/ports/event_publisher.py`
- `application/ports/repositories/__init__.py`, `application/ports/repositories/<aggregate>.py`
- `application/errors.py`

**По концепциям, упомянутым пользователем:**
- CQRS-термины: «use case», «сценарий», «command», «команда» в смысле прикладного действия, «query», «запрос».
- DTO, маппинг доменного объекта в DTO.
- Unit of Work, UoW, граница транзакции на уровне сценария.
- Порт, port, адаптер; EventPublisher; outbox-публикация.
- Иерархия прикладных ошибок (`AppError`, `AppNotFoundError`, `AppInvalidDataError`, `AppInternalError`).
- Авторизация инициатора, role check.
- Прикладной слой, application layer.

**По типам задач:**
- Добавление нового use case (команды или запроса).
- Добавление нового DTO.
- Расширение `UnitOfWork` под новый агрегат.
- Добавление нового интерфейса репозитория или новой группы (`outbox`, `subscription`).
- Добавление события в outbox + соответствующий publisher use case.
- Расширение иерархии прикладных ошибок.
- Правка списочных запросов (filter helper, paginator).

### Анти-триггеры

Скил не активируется, когда правка относится к слоям `domain/`, `infrastructure/` или `presentation/` — для редактирования каждого из этих слоёв используется свой скил:
- `domain/` — доменная модель: агрегаты, value objects, фабрики, доменные сервисы, абстрактные domain-интерфейсы.
- `infrastructure/` — реализации портов: репозитории к БД, адаптеры к брокеру сообщений, миграции схемы БД.
- `presentation/` — точки входа в систему: HTTP-эндпоинты, фоновые worker-ы, схемы валидации входящих данных.

Также не активируется на косметические правки внутри `application/` (только docstrings, переименование без изменения контракта, импорт-рефакторинг).

### Предусловия

- Гексагональная архитектура с выделенным `application/`-слоем.
- CQRS: команды и запросы разнесены по разным деревьям.
- `application/` импортирует только из `domain/` и стандартной библиотеки. Запрещены импорты из `infrastructure/`, `presentation/`. Внешние библиотеки (web-фреймворки, драйверы БД, клиенты брокеров и т.п.) не используются.
- В проекте есть domain-слой с агрегатами, VO, доменными сервисами и абстрактными domain-репозиториями. При отсутствии или неполноте домена — согласование с пользователем до начала работы.
- В проекте есть per-aggregate authorization-сервис в domain (или эквивалент). При отсутствии — согласование с пользователем.

## Package Structure

```
application/
├── __init__.py                              ← пустой
├── errors.py                                ← иерархия AppError
│
├── dto/
│   ├── __init__.py                          ← пустой
│   ├── paginators.py                        ← LimitOffsetPaginator и общие пагинаторы
│   └── <aggregate>.py                       ← <Aggregate>SimpleDTO + <Aggregate>VersionSimpleDTO
│
├── ports/
│   ├── __init__.py                          ← пустой
│   ├── unit_of_work.py                      ← UnitOfWork ABC + property на репо-группы
│   ├── event_publisher.py                   ← EventPublisher ABC + Union по VersionDTO
│   └── repositories/
│       ├── __init__.py                      ← НЕ пустой: <Aggregate>Repositories группы + __all__
│       └── <aggregate>.py                   ← read/version/outbox/subscription интерфейсы
│                                              + <Aggregate>Event + <Aggregate>VersionDTO
│
├── commands/
│   ├── __init__.py                          ← пустой
│   ├── base.py                              ← BaseUseCase + PublisherUseCase (пример конвенции)
│   ├── public/
│   │   ├── __init__.py                      ← пустой
│   │   └── <aggregate>/
│   │       ├── __init__.py                  ← НЕ пустой: re-export use case-ов агрегата
│   │       ├── base.py                      ← опционально: общий helper для 2+ use case-ов
│   │       └── <action>.py                  ← один use case на файл
│   └── private/
│       ├── __init__.py                      ← пустой
│       └── <aggregate>/
│           ├── __init__.py                  ← НЕ пустой: re-export use case-ов агрегата
│           └── <action>.py
│
└── queries/
    ├── __init__.py                          ← пустой
    ├── base.py                              ← BaseUseCase (без PublisherUseCase)
    └── public/
        ├── __init__.py                      ← пустой
        └── <aggregate>/
            ├── __init__.py                  ← НЕ пустой: re-export use case-ов агрегата
            ├── base.py                      ← опционально: общий helper для 2+ use case-ов
            └── <action>.py
```

### Назначение узлов

| Узел | Что внутри | Канон |
|---|---|---|
| `errors.py` | `AppError` + `AppNotFoundError`, `AppInvalidDataError`, `AppInternalError` | один файл, не дробится |
| `dto/<aggregate>.py` | DTO агрегата: `<Aggregate>SimpleDTO` + `<Aggregate>VersionSimpleDTO` | по одному файлу на агрегат |
| `dto/paginators.py` | общие пагинаторы (`LimitOffsetPaginator`) | один на проект |
| `ports/unit_of_work.py` | `UnitOfWork` ABC: `__aenter__`/`__aexit__` + property на группы | один файл |
| `ports/event_publisher.py` | `EventPublisher` ABC + `PublishEventDTO = Union[...]` | один файл |
| `ports/repositories/__init__.py` | dataclass-группы `<Aggregate>Repositories(slots=True)` + `__all__` | **единственный непустой `__init__.py` в слое** |
| `ports/repositories/<aggregate>.py` | read-репозиторий (наследник доменного), `<Aggregate>Event`, `<Aggregate>VersionDTO`, version/outbox/subscription интерфейсы | по одному файлу на агрегат |
| `commands/base.py` / `queries/base.py` | базовые классы use case-ов (если приняты в проекте) | пример конвенции, не предписание |
| `commands/{public,private}/<aggregate>/<action>.py` | один use case = один файл: dataclass-команда + use case-класс | каждый файл публичный |
| `queries/public/<aggregate>/<action>.py` | dataclass-запрос + use case-класс | то же |
| `commands/{public,private}/<aggregate>/base.py` <br> `queries/public/<aggregate>/base.py` | **опционально**: общий helper для 2+ use case-ов одной группы | создаётся, только когда 2+ use case-а делят helper |

### Конвенции по `__init__.py`

| Уровень | Состояние | Содержимое |
|---|---|---|
| `application/__init__.py` | пустой | — |
| `application/{commands,queries,dto,ports}/__init__.py` | пустой | — |
| `application/commands/{public,private}/__init__.py` | пустой | — |
| `application/queries/public/__init__.py` | пустой | — |
| **`application/commands/{public,private}/<aggregate>/__init__.py`** | **не пустой** | re-export всех use case-ов агрегата + Command-dataclasses, объединённый `__all__` |
| **`application/queries/public/<aggregate>/__init__.py`** | **не пустой** | re-export всех use case-ов агрегата + Query-dataclasses, объединённый `__all__` |
| `application/dto/__init__.py` | пустой | DTO импортируются напрямую из `application.dto.<aggregate>` |
| `application/ports/__init__.py` | пустой | — |
| **`application/ports/repositories/__init__.py`** | **не пустой** | dataclass-группы `<Aggregate>Repositories(slots=True)` + `__all__` |

Импорты из presentation — через `<aggregate>/__init__.py` витрину: `from application.commands.public.tenant import UpdateTenantUseCase, UpdateTenantCommand`. Изнутри одного use case-файла — прямой путь (`from application.commands.base import BaseUseCase`).

### Naming convention для use case-ов (CQRS verb-first)

**Команды — императивный verb + аггрегат:**

| Файл | Command | UseCase |
|---|---|---|
| `create.py` | `Create<Aggregate>Command` | `Create<Aggregate>UseCase` |
| `update.py` | `Update<Aggregate>Command` | `Update<Aggregate>UseCase` |
| `delete.py` | `Delete<Aggregate>Command` | `Delete<Aggregate>UseCase` |
| `restore.py` | `Restore<Aggregate>Command` | `Restore<Aggregate>UseCase` |
| `publish.py` | — (нет входа) | `Publish<Aggregate>VersionsUseCase` |
| `<verb>_<object>.py` (доменный) | `<Verb><Aggregate><Object>Command` | `<Verb><Aggregate><Object>UseCase` |

**Запросы — `Get` / `List` + описание возвращаемого результата:**

| Файл | Query | UseCase |
|---|---|---|
| `retrieve_last_version.py` | `Get<Aggregate>LastVersionQuery` | `Get<Aggregate>LastVersionUseCase` |
| `retrieve_version.py` | `Get<Aggregate>VersionQuery` | `Get<Aggregate>VersionUseCase` |
| `list_last_versions.py` | `List<Aggregate>LastVersionsQuery` | `List<Aggregate>LastVersionsUseCase` |
| `list_versions.py` | `List<Aggregate>VersionsQuery` | `List<Aggregate>VersionsUseCase` |

Имена файлов следуют столбцу «Файл» — это часть структуры слоя, не имя класса.

Имена событий (`<Aggregate>Event` в `ports/repositories/<aggregate>.py`) живут по отдельному правилу: noun + past (`Created`, `Updated`, `Deleted`, `Restored`).

### Чего в layout-е нет и почему

- **Нет `queries/private/`** — у запросов нет «системной» аудитории; всё чтение инициируется пользователем. При появлении реальной потребности — следовать паттерну `queries/private/<aggregate>/<action>.py` без `initiator` и без авторизации.
- **Нет `events.py` или подобного агрегатного файла** — `<Aggregate>Event` (StrEnum) живёт рядом с интерфейсами репозиториев в `ports/repositories/<aggregate>.py`, потому что событие относится к контракту версионного репозитория.

## Errors Hierarchy

### Полная иерархия

```
AppError (msg, action, data)
├── AppNotFoundError       — основной ресурс не найден
├── AppInvalidDataError    — зависимость/контекст невалиден или отсутствует
└── AppInternalError       — внутренняя ошибка слоя/инфраструктуры (+ wrap_error)
```

Иерархия живёт в одном файле — `application/errors.py`. Per-aggregate подклассов **по умолчанию не вводим** — агрегат живёт в `data`, не в имени класса. Расширение иерархии (новые подклассы для специфичных случаев) — по согласованию с пользователем.

### Базовый класс

```python
from typing import Any


class AppError(Exception):
    def __init__(
        self,
        msg: str,
        action: str,
        data: dict[str, Any] | None = None,
        *args: object,
    ) -> None:
        super().__init__(msg, *args)
        self.msg = msg
        self.action = action
        self.data = data or {}


class AppNotFoundError(AppError):
    pass


class AppInvalidDataError(AppError):
    pass


class AppInternalError(AppError):
    def __init__(
        self,
        msg: str,
        action: str,
        data: dict[str, Any] | None = None,
        wrap_error: BaseException | None = None,
        *args: object,
    ) -> None:
        super().__init__(msg, action, data, *args)
        self.wrap_error = wrap_error
```

### Поля

- **`msg`** — короткое человекочитаемое описание на русском, без переменных. Пример: `"арендатор не существует"`, `"транзакция уже опубликована"`, `"инициатор не существует"`.
- **`action`** — контекст операции, в которой возникла ошибка. Совпадает с локальной `action` use case-а. Пример: `"обновление арендатора"`, `"удаление транзакции"`, `"получение последних версий категорий"`.
- **`data`** — структурированный контекст ошибки для логов и API-ответов. Опционально, по умолчанию `{}`.
- **`wrap_error`** (только `AppInternalError`) — оригинальное исключение, если ошибка оборачивает техническое.

### Конвенция формирования `data`

**Ключи верхнего уровня — английские, в snake_case, отражают тип сущности:**

| Тип ошибки | Ключ верхнего уровня | Значение |
|---|---|---|
| Ошибка одного агрегата | имя сущности в ед. ч.: `"tenant"`, `"transaction"`, `"category"`, `"user"` | `dict` с полями этой сущности |
| Ошибка с участием нескольких сущностей одного типа | имя во мн. ч.: `"categories"`, `"transactions"` | `list[dict]` |
| Ошибка отдельного значения / поля | имя поля: `"version"`, `"event"`, `"status"` | примитив или `dict` |

**Внутри блока сущности — поля в snake_case (английские), значения — примитивы для JSON:**

```python
# Ошибка одного агрегата
{"tenant": {"tenant_id": UUID(...)}}

# Ошибка с двумя сущностями разных типов
{
    "tenant": {"tenant_id": UUID(...)},
    "transaction": {"transaction_id": UUID(...)},
}

# Ошибка с коллекцией зависимостей
{
    "transaction": {"transaction_id": UUID(...)},
    "categories": [
        {"category_id": UUID(...)},
        {"category_id": UUID(...)},
    ],
}

# Ошибка отдельного значения
{"event": "wrong_value"}
{"version": 0}
```

**Правила значений:**
- `UUID` оставляем как `UUID`-объект, не строкой — сериализатор API сам приведёт.
- `Decimal` приводим к `str` (`str(amount)`), чтобы избежать потери точности при JSON-сериализации.
- `datetime` оставляем как есть, сериализатор API приведёт.
- `Enum` берём `.value` (строку), не сам enum.
- Доменные VO в значениях не появляются — всегда разворачиваем в примитив (`tenant_id.tenant_id`, `status.value`).

### Выбор типа ошибки

| Условие | Тип |
|---|---|
| Ресурс — цель операции (существительное в имени use case-а) | `AppNotFoundError` |
| Ресурс — зависимость/контекст (упоминается в команде, но не цель) | `AppInvalidDataError` |
| Initiator (всегда) | `AppInvalidDataError` |
| Use case создания: цели ещё нет, все загружаемые суть зависимости | `AppInvalidDataError` |
| List-запрос: пустой список валиден | ничего не бросается |
| Невалидное внутреннее состояние, impossible-кейс, обёртка тех.исключения | `AppInternalError` |

Цель операции определяется механически: существительное в имени класса use case-а. `UpdateTenantUseCase` → цель = `Tenant` → `tenant_id` даёт NotFound. `AppointUserAdminUseCase` → цель = `User` → `user_id` даёт NotFound. Зависимости (`category_id` в `CreateTransactionUseCase`) → InvalidData.

### Правила вызова

- **Всегда через kwargs.** `raise AppNotFoundError(msg="...", action=action, data={...})`.
- **`data` пропускаем, если её нет** — не передавать `data={}` явно.
- **`wrap_error` пропускаем, если его нет** — не передавать `wrap_error=None` явно.
- **`AppError` напрямую не инстанцируется** — только подклассы.

## Public API of Module

### Что попадает в витрину `<aggregate>/__init__.py`

В `application/commands/{public,private}/<aggregate>/__init__.py` и `application/queries/public/<aggregate>/__init__.py` re-export-ятся:

| Категория | Примеры |
|---|---|
| Use case-классы | `UpdateTenantUseCase`, `GetTenantLastVersionUseCase` |
| Соответствующие Command/Query dataclass-ы | `UpdateTenantCommand`, `GetTenantLastVersionQuery` |

**Не попадает:**
- Helper-методы из `<aggregate>/base.py` (приватные, внутреннее использование).
- Базовые классы из `commands/base.py` / `queries/base.py` — импортируются напрямую.

### Шаблон `<aggregate>/__init__.py`

```python
from application.commands.public.tenant.delete import (
    DeleteTenantCommand,
    DeleteTenantUseCase,
)
from application.commands.public.tenant.restore import (
    RestoreTenantCommand,
    RestoreTenantUseCase,
)
from application.commands.public.tenant.update import (
    UpdateTenantCommand,
    UpdateTenantUseCase,
)

__all__ = [
    "DeleteTenantCommand",
    "DeleteTenantUseCase",
    "RestoreTenantCommand",
    "RestoreTenantUseCase",
    "UpdateTenantCommand",
    "UpdateTenantUseCase",
]
```

**`__all__` строго в алфавитном порядке.**

### `ports/repositories/__init__.py` — единственный непустой среди `ports/`

```python
from dataclasses import dataclass

from application.ports.repositories.tenant import (
    TenantEvent,
    TenantOutboxRepository,
    TenantReadRepository,
    TenantVersionDTO,
    TenantVersionRepository,
)
# ... аналогично для других агрегатов

__all__ = [
    "TenantEvent",
    "TenantOutboxRepository",
    "TenantReadRepository",
    "TenantRepositories",
    "TenantVersionDTO",
    "TenantVersionRepository",
    # ...
]


@dataclass(slots=True)
class TenantRepositories:
    read: TenantReadRepository
    version: TenantVersionRepository
    outbox: TenantOutboxRepository
    # subscription, если применимо
```

### Top-level `application/__init__.py` — пустой

Не делаем re-export на верхний уровень. Импорты на стороне идут через `<aggregate>/__init__.py` витрины (для use case-ов) или прямые пути (для DTO, ошибок, базовых классов).

### Правила импорта

| Где | Откуда импортируем |
|---|---|
| Из `application/commands/<.../<aggregate>/<action>.py` | Прямые пути: `from application.commands.base import BaseUseCase`, `from application.dto.tenant import TenantSimpleDTO`, `from application.errors import AppNotFoundError`, `from domain.tenant import TenantID, TenantPolicyService` |
| Из `application/queries/<.../<aggregate>/<action>.py` | Аналогично |
| Из `presentation/` | Витрина: `from application.commands.public.tenant import UpdateTenantUseCase, UpdateTenantCommand` |
| Из `infrastructure/` (для имплементации портов) | Прямые пути: `from application.ports.repositories.tenant import TenantReadRepository` |

## Anti-patterns (сводный чеклист)

### Утечка слоёв
- Импорт из `infrastructure/` или `presentation/` в `application/`.
- Импорт внешних библиотек в `application/`.
- Domain VO/entity в полях команд/запросов.
- Domain VO/entity в return type `execute`.
- Domain VO/entity в значениях `data` ошибки.
- Re-export use case-ов из верхнеуровневых `__init__.py` (только агрегатный уровень).

### Транзакционные границы
- Вложенный `async with self._uow` в одном `execute`.
- Доступ к репозиториям через `self._uow.<...>` вместо локального `uow` после `async with`.
- Несколько последовательных `async with` в **команде** (для запросов — допустимо, для мутаций нет).
- Helper-метод, работающий с репозиториями, без `uow`-параметра.
- Хранение `uow` в state объекта.

### Авторизация
- Любая авторизация в private use case (там нет initiator).
- Загрузка агрегатов **до** проверки роли инициатора.
- Глобальная проверка роли без последующего per-aggregate authorization-сервиса (для public-команды над конкретным агрегатом).
- `_initiator` вне `async with` — нужен открытый `uow`.

### Команды, запросы, DTO
- Команда/запрос/DTO без `@dataclass(slots=True, frozen=True)`.
- Поля команд/запросов: VO, domain entity, response-DTO, типы presentation/infrastructure.
- Конверсия примитивов в VO внутри команды (`__post_init__` и т.п.) — конверсия в use case.
- `execute` с двумя+ аргументами — только 0 или 1.
- DTO с методами поведения (валидации, вычисления) — только `from_*` фабрики.
- Вложенные DTO в `<Aggregate>SimpleDTO` — плоско.
- `to_dict` / `to_json` / `model_dump` в DTO — сериализация это presentation.

### Ports
- Тело в абстрактном методе — должен быть `...`.
- Реализация в `ports/` — реализации в `infrastructure/`.
- Разбиение `ports/repositories/<aggregate>.py` на под-файлы — один файл на агрегат.
- `<Aggregate>Event` без `from_str`.
- `<Aggregate>Repositories` с `frozen=True`.

### Ошибки
- f-строки в `msg`.
- Позиционные аргументы при создании ошибки.
- `data={}` явным пустым литералом — параметр опускается.
- VO/entity в значениях `data` — развёрнуто в примитивы.
- `try/except AppError` в use case — control flow слоя ловить нельзя.
- Прямой `raise AppError(...)` — только подклассы.
- Per-aggregate подклассы (`TenantNotFoundError` и т.п.) по умолчанию не вводятся.
- Бизнес-логика в `execute`, минуя domain.

### Outbox / publisher
- `event_publisher.publish` прямо из обычной command use case (нарушение outbox-паттерна).
- Publisher use case с командой на вход.
- Одиночная публикация вместо `batch_publish` в publisher.
- `version.save` без предшествующего `read.save` — состояние и аудит идут парой.
- `outbox.save` у агрегата без `outbox`-поля в `<Aggregate>Repositories`.

### Naming и структура
- Имена use case-ов с `-ion` / `-ing` / agent-noun — только verb-first (`CreateTenant`, `GetTenantLastVersion`).
- Команда без суффикса `Command`, запрос без суффикса `Query`.
- Несколько use case-ов в одном файле.
- Имя файла, не совпадающее с действием.
- DTO без суффикса `Simple` для базовых случаев.
- Команда/запрос с `<Aggregate><Action>` ordering вместо verb-first.

## References

- **`references/use_cases.md`** — анатомия use case-а: базовые классы, конструктор, шаблон `execute` с фазами, initiator + role, per-aggregate authorization, транзакционные границы UoW, обработка ошибок.
- **`references/commands_and_queries.md`** — формы команд и запросов, допустимые типы полей, конверсия в VO, return-type правило, контракт `execute`, command vs query, helper `_filtering_data`.
- **`references/dtos.md`** — DTO как граница слоя: форма, типы полей, фабрики `from_domain`/`from_dto`, naming с `Simple`-суффиксом, расположение, сценарные DTO.
- **`references/ports.md`** — порты: `UnitOfWork`, `EventPublisher`, repository-интерфейсы (`Read`, `Version`, `Outbox`, `Subscription`), группы `<Aggregate>Repositories`, импорты в `ports/`.
- **`references/outbox_publisher.md`** — outbox pattern: зачем, форма publisher use case, шаблон, отличия от обычной команды, запрет публикации из команды.
- **`references/checklists.md`** — пошаговые чек-листы добавления команды, запроса, DTO, портов нового агрегата, publisher use case-а.
