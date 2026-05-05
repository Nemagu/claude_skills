---
name: python-ddd-domain-layer-writing
description: Используй при проектировании или правке доменного слоя в Python-проекте по DDD/гексагональной архитектуре. Триггеры — добавление или изменение агрегата, проекции, value object, доменного сервиса, фабрики, абстрактного repository-интерфейса в `domain/`; реализация инвариантов и поведения сущности; работа с версионированием, доменными ошибками и состояниями агрегата. Не применять для слоёв `application/`, `infrastructure/`, `presentation/`.
---

# Python DDD Domain Layer Writing

## Quick Start

1. Определи: новая сущность — агрегат (источник правды здесь) или проекция (источник правды снаружи)?
2. Сколько состояний — два (`ACTIVE`/`DELETED`) или больше? Это определяет выбор базового класса.
3. Создай поддиректорию `domain/<name>/` и последовательно: `value_objects.py` → `entity.py` (или `projection.py`) → `factory.py` → опционально `repository.py` и `services.py`.
4. Обнови витрину `__init__.py` поддиректории.
5. Любые мутации агрегата идут по шаблону: `_check_state()` → проверка идемпотентности → мутация → `_update_version()`.
6. Применения событий к проекции: проверка идемпотентности → мутация. **Без `_check_state` и без `_update_version`.**
7. Доменные ошибки бросаются с kwargs (`msg=`, `subject=`, `data=`). `data` — английский snake_case ключ-сущность на верхнем уровне.
8. ID между связанными агрегатами и проекциями совпадает (ID-parity). Локальный агрегат и проекция той же внешней сущности — два разных класса с одинаковым `UUID`.
9. Внутри `domain/` запрещены импорты из `application/`, `infrastructure/`, `presentation/`. Никаких внешних зависимостей кроме стандартной библиотеки.
10. Все VO иммутабельны (`@dataclass(frozen=True)` или `StrEnum`).
11. Все приватные поля начинаются с `_` и экспонируются read-only `@property` без сеттера.
12. Если задача не вписывается в описанные паттерны — действуй по общему контракту соответствующего типа и согласуй решение с пользователем.

## When to Apply

### Триггеры активации

**По расположению файлов** — любая правка/создание в `domain/`:
- `domain/<aggregate>/entity.py`, `domain/<aggregate>/factory.py`, `domain/<aggregate>/services.py`, `domain/<aggregate>/repository.py`, `domain/<aggregate>/value_objects.py`
- `domain/<projection>/projection.py` и связанные
- Общие файлы: `domain/value_objects.py`, `domain/errors.py`, `domain/entities.py`, `domain/projections.py`

**По концепциям, упомянутым пользователем:**
- DDD-термины: «агрегат», «aggregate», «value object», «VO», «доменная сущность», «entity», «проекция», «projection», «доменный сервис», «domain service», «фабрика», «factory», «репозиторий-интерфейс».
- Бизнес-инварианты, инкапсуляция бизнес-логики, неизменяемость состояния.
- Оптимистичный параллелизм / версионирование агрегата.
- Управление состоянием сущности (`active`/`deleted`/`frozen`).
- Read-модели, проекции из других bounded context.

**По типам задач:**
- Добавление нового агрегата или проекции.
- Добавление/изменение VO.
- Добавление/изменение метода поведения агрегата (нового мутатора).
- Добавление доменного сервиса (creation/uniqueness/policy).
- Добавление абстрактного repository-интерфейса в domain.
- Расширение иерархии доменных ошибок.

### Анти-триггеры

- Правка `application/` (use cases, commands, queries, DTO, ports).
- Правка `infrastructure/` (psycopg-репозитории, NATS-адаптеры, миграции).
- Правка `presentation/` (FastAPI routers, background workers).
- Импорт-рефакторинг, переименование без изменения структуры.

### Предусловия

- Проект следует гексагональной архитектуре с выделенным `domain/`-слоем.
- В `domain/` запрещены импорты из `application/`, `infrastructure/`, `presentation/`. Допустимы только импорты внутри `domain/` и из стандартной библиотеки.
- В проекте применяется DDD-подход: агрегаты с богатым поведением, VO, фабрики, доменные сервисы.

## Package Structure

```
domain/
├── __init__.py                  ← пустой, не делаем re-export верхнего уровня
│
├── value_objects.py             ← общие VO (Version, AggregateName, ProjectionName, State)
├── errors.py                    ← иерархия доменных ошибок
├── entities.py                  ← базовые Entity / EntityWithState
├── projections.py               ← базовые Projection / ProjectionWithState
│
├── <aggregate_name>/            ← поддиректория на агрегат
│   ├── __init__.py              ← re-export публичного API через __all__
│   ├── entity.py
│   ├── value_objects.py
│   ├── factory.py
│   ├── repository.py            ← опционально
│   └── services.py              ← опционально
│
└── <projection_name>/           ← поддиректория на проекцию
    ├── __init__.py
    ├── projection.py            ← вместо entity.py!
    ├── value_objects.py
    ├── factory.py
    ├── repository.py
    └── services.py              ← опционально
```

### Содержимое верхнеуровневых файлов

**`domain/value_objects.py`** — VO, разделяемые между агрегатами/проекциями. Правило: VO попадает сюда, **только если используется ≥ 2 разными модулями ИЛИ базовыми классами**. Иначе — в `domain/<name>/value_objects.py`.

**`domain/errors.py`** — единая иерархия доменных ошибок. Кастомные исключения per-aggregate **не создаём**.

**`domain/entities.py`** — базовые `Entity` и `EntityWithState`. Других классов в этом файле быть не должно.

**`domain/projections.py`** — базовые `Projection` и `ProjectionWithState`.

### Правила выбора: агрегат vs проекция

**Агрегат**, если объект:
- Источник правды для своих данных в этом BC.
- Имеет команды-мутаторы, защищающие инварианты.
- Версионируется самим собой через `_update_version()` после каждой мутации.

**Проекция**, если объект:
- Read-модель из другого BC (приходит через события/репликацию).
- Получает версию извне с событиями, не инкрементит сам.
- В файле — `projection.py` (не `entity.py`), наследует `Projection` / `ProjectionWithState`.

### Правила импортов внутри `domain/`

**Разрешено:**
- Импорт из стандартной библиотеки (`uuid`, `decimal`, `datetime`, `enum`, `dataclasses`, `typing`, `abc`).
- Импорт между модулями `domain/` (например, `from domain.tenant import TenantID` в `personal_transaction/entity.py`).
- Импорт из общих файлов (`domain.value_objects`, `domain.errors`, `domain.entities`, `domain.projections`).

**Запрещено:**
- Импорты из `application/`, `infrastructure/`, `presentation/`.
- Импорты внешних библиотек (никаких `pydantic`, `psycopg`, `fastapi`).
- Циклические импорты между поддиректориями. При риске цикла — выносим общий VO в `domain/value_objects.py`.

### Именование

- Модуль агрегата/проекции — **snake_case в единственном числе** (`personal_transaction`, не `personal_transactions`).
- Класс агрегата — **PascalCase, существительное в единственном числе** (`PersonalTransaction`, `Tenant`).
- ID-VO — **`<Aggregate>ID`** (`PersonalTransactionID`, не `PersonalTransactionId`).
- Фабрика — **`<Aggregate>Factory`**.
- Repository-интерфейс — **`<Aggregate>ReadRepository`**.
- Сервисы — **`<Aggregate>CreationService`** / **`<Aggregate>UniquenessService`** / **`<Aggregate>PolicyService`**.

## Error Hierarchy

### Полная иерархия

```
DomainError (msg, subject, data)
├── ValueObjectError
│   └── ValueObjectInvalidDataError
└── EntityError
    ├── EntityInvalidDataError
    ├── EntityVersionLessThenCurrentError
    ├── EntityIdempotentError
    ├── EntityPolicyError
    └── EntityAlreadyExistsError
```

Вся иерархия живёт в `domain/errors.py`. Кастомные исключения per-aggregate **не создаём**.

### Базовый класс

```python
from typing import Any


class DomainError(Exception):
    def __init__(
        self,
        msg: str,
        subject: str,
        data: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(msg)
        self.msg = msg
        self.subject = subject
        self.data = data or {}

    def __repr__(self) -> str:
        return (
            f"{self.__class__.__name__}("
            f"msg={self.msg!r}, subject={self.subject!r}, data={self.data!r})"
        )


class ValueObjectError(DomainError):
    pass


class ValueObjectInvalidDataError(ValueObjectError):
    pass


class EntityError(DomainError):
    pass


class EntityInvalidDataError(EntityError):
    pass


class EntityVersionLessThenCurrentError(EntityError):
    pass


class EntityIdempotentError(EntityError):
    pass


class EntityPolicyError(EntityError):
    pass


class EntityAlreadyExistsError(EntityError):
    pass
```

### Поля

- **`msg`** — сообщение об ошибке на языке домена. Пример: `"новое состояние идентично текущему"`, `"арендатор удален"`, `"только владелец может работать с категорией"`.
- **`subject`** — человекочитаемая метка предмета ошибки на языке домена. Это **не** имя класса/модуля, а название агрегата/VO/проекции в терминах бизнеса. Берётся из `aggregate_name.name` для агрегата, `projection_name.name` для проекции, явная строка для VO. Примеры: `"арендатор"`, `"категория транзакций"`, `"проекция пользователя"`, `"название категории"`, `"версия агрегата"`.
- **`data`** — структурированный контекст ошибки для логов и API-ответов. Опционально, по умолчанию `{}`.

### Конвенция формирования `data`

**Ключи верхнего уровня — английские, в snake_case, отражают тип сущности:**

| Тип ошибки | Ключ верхнего уровня | Значение |
|---|---|---|
| Ошибка одного агрегата | имя сущности в ед. ч.: `"tenant"`, `"transaction"`, `"category"`, `"user"` | `dict` с полями этой сущности |
| Ошибка с участием нескольких сущностей одного типа | имя во мн. ч.: `"categories"`, `"transactions"` | `list[dict]` |
| Ошибка VO | имя поля VO: `"version"`, `"name"`, `"transaction_type"` | примитив или `dict` |

**Внутри блока сущности — поля в snake_case (английские), значения — примитивы для JSON:**

```python
# Ошибка одного агрегата
{"tenant": {"tenant_id": UUID(...), "state": "active"}}

# Ошибка с двумя агрегатами разных типов
{
    "tenant": {"tenant_id": UUID(...)},
    "transaction": {"owner_id": UUID(...)},
}

# Ошибка с коллекцией
{
    "transaction": {"transaction_id": UUID(...)},
    "categories": [
        {"category_id": UUID(...), "name": "еда"},
        {"category_id": UUID(...), "name": "транспорт"},
    ],
}

# Ошибка VO
{"version": 0}
{"transaction_type": "wrong_value"}
{"money_amount": {"amount": "-10.50", "currency": "ruble"}}
```

**Правила значений:**
- `UUID` оставляем как `UUID`-объект, не строкой — сериализатор API сам приведёт.
- `Decimal` приводим к `str` (`str(amount)`), чтобы избежать потери точности при JSON-сериализации.
- `datetime` оставляем как есть, сериализатор API приведёт.
- `Enum` берём `.value` (строку), не сам enum.

### Семантика подклассов

| Класс | Когда бросать |
|---|---|
| `ValueObjectInvalidDataError` | VO получил невалидные данные при конструировании. В `__post_init__` или `from_str`. |
| `EntityInvalidDataError` | Операция над сущностью невозможна из-за её состояния или входных данных, не подпадающих под идемпотентность/политику. Типичные случаи: попытка изменить удалённую сущность (через `_check_state`), пустые данные на входе, несовместимые входные данные. |
| `EntityVersionLessThenCurrentError` | Попытка обновить **проекцию** версией меньше текущей. Только в `Projection.new_version`. |
| `EntityIdempotentError` | Операция была бы no-op — новое значение равно текущему. В мутаторах после `_check_state` и в `Projection.new_version` при равенстве версий. |
| `EntityPolicyError` | Нарушение бизнес-политики, не связанное с состоянием самой сущности (только владелец может, только админ может, доступ запрещён из-за состояния субъекта). |
| `EntityAlreadyExistsError` | Попытка создать сущность, которая уже существует. В Creation и Uniqueness сервисах. |

### Правила вызова

- **Всегда через kwargs.** `raise EntityIdempotentError(msg="...", subject="...", data={...})`.
- **`data` пропускаем, если её нет** — не передавать `data={}` явно.
- **В агрегатах используем `_error_data` хелпер** — он подставляет `subject` из `aggregate_name.name` и добавляет ID агрегата в `data`: `raise EntityIdempotentError(**self._error_data(msg="...", data={...}))`.
- **В VO и в сервисах** заполняем поля явно (хелпера нет).

## Public API of a Module (`__init__.py` and `__all__`)

### Что попадает в витрину

| Категория | Примеры |
|---|---|
| Класс агрегата / проекции | `Tenant`, `User` |
| Фабрика | `TenantFactory`, `UserFactory` |
| Все VO агрегата/проекции | `TenantID`, `TenantState`, `TenantStatus` |
| Repository-интерфейс (если есть) | `TenantReadRepository` |
| Domain-сервисы (если есть) | `TenantCreationService`, `UserUniquenessService` |

**Не попадает:**
- Приватные хелперы (имя с `_`).
- Базовые классы из общих файлов (`Entity`, `Projection`, `DomainError`) — импортируются напрямую.

### Шаблон `__init__.py`

```python
from domain.<aggregate>.entity import <Aggregate>
from domain.<aggregate>.factory import <Aggregate>Factory
from domain.<aggregate>.repository import <Aggregate>ReadRepository
from domain.<aggregate>.services import (
    <Aggregate>CreationService,
    <Aggregate>PolicyService,
)
from domain.<aggregate>.value_objects import (
    <Aggregate>ID,
    <Aggregate>Name,
    <Aggregate>State,
)

__all__ = [
    "<Aggregate>",
    "<Aggregate>CreationService",
    "<Aggregate>Factory",
    "<Aggregate>ID",
    "<Aggregate>Name",
    "<Aggregate>PolicyService",
    "<Aggregate>ReadRepository",
    "<Aggregate>State",
]
```

**`__all__` строго в алфавитном порядке.**

### Top-level `domain/__init__.py` — пустой

Не делаем re-export всех агрегатов на верхний уровень. Импорты на стороне идут через поддиректории.

### Правила импорта

| Где | Откуда импортируем |
|---|---|
| Внутри `domain/<aggregate>/*.py` (тот же модуль) | Прямые пути: `from domain.<aggregate>.entity import ...` |
| Из `domain/<other_aggregate>/*.py` | Витрина: `from domain.<other_aggregate> import ...` |
| Из `application/`, `infrastructure/`, `presentation/` | Витрина: `from domain.<aggregate> import ...` |
| Общие файлы (`domain/entities.py`, `domain/errors.py`, ...) | Прямые пути: `from domain.errors import ...` |

## References

- **`references/value_objects.md`** — три типа VO (Identity, Validated, Enum) + Multi-field, правила иммутабельности, нормализация, валидация.
- **`references/aggregates.md`** — базовые классы `Entity` / `EntityWithState`, паттерны агрегатов, фабрики агрегатов, особый случай расширенного состояния.
- **`references/projections.md`** — базовые классы `Projection` / `ProjectionWithState`, паттерны проекций, фабрики проекций, ID-parity, паттерн подписки.
- **`references/services_and_repositories.md`** — общий контракт domain-сервисов, три распространённых типа (Creation, Uniqueness, Policy), repository-интерфейсы в domain.
- **`references/checklists.md`** — пошаговые чек-листы добавления агрегата и проекции.
