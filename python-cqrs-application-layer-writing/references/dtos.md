# DTOs

## Форма

`@dataclass(slots=True, frozen=True)`. DTO — иммутабельный snapshot для пересечения границы слоя в направлении «application → presentation».

```python
from dataclasses import dataclass
from typing import Self
from uuid import UUID

from domain.tenant import Tenant


@dataclass(slots=True, frozen=True)
class TenantSimpleDTO:
    tenant_id: UUID
    name: str
    status: str
    state: str
    version: int

    @classmethod
    def from_domain(cls, tenant: Tenant) -> Self:
        return cls(
            tenant_id=tenant.tenant_id.tenant_id,
            name=tenant.name.name,
            status=tenant.status.value,
            state=tenant.state.value,
            version=tenant.version.version,
        )
```

**Правила:**
- `@dataclass(slots=True, frozen=True)` — обязательно.
- Поля — только примитивы / типы стандартной библиотеки, развёрнутые из domain-объектов. Никаких domain-ссылок.
- Кроме полей, у DTO допустимы только **classmethod-фабрики** (`from_domain` / `from_dto`). Никаких других методов.

## Допустимые типы полей

| Категория DTO | Допустимые поля | Запрещено |
|---|---|---|
| **Базовый (`Simple`)** | примитивы, stdlib-даты, `T | None`, `list[T]`, `tuple[T, ...]` | вложенные DTO, domain VO/entities, ссылки на репозитории/UoW/publisher, методы кроме `from_*` фабрик |
| **Сценарный (композитный)** | то же, что в Simple, **+ вложенные DTO** | то же, кроме вложения; форма обсуждается с пользователем |

**Скалярные примитивы**: `UUID`, `int`, `str`, `bool`, `float`, `Decimal`.

**Дата/время (stdlib)**: `datetime`, `date`, `time`.

## Фабрики

Две формы, в зависимости от источника:

| Фабрика | Источник | Когда применяется |
|---|---|---|
| `from_domain(cls, aggregate: <Aggregate>) -> Self` | доменный агрегат напрямую | DTO текущего состояния (`<Aggregate>SimpleDTO`) |
| `from_dto(cls, dto: <Aggregate>VersionDTO) -> Self` | port-level DTO из `application/ports/repositories/<aggregate>.py` | DTO версионного снапшота (`<Aggregate>VersionSimpleDTO`) |

Обе — `@classmethod`. Тело: разворачивает VO/доменные объекты в примитивы, без вычислений и без I/O.

```python
# from_domain — из агрегата Tenant
@classmethod
def from_domain(cls, tenant: Tenant) -> Self:
    return cls(
        tenant_id=tenant.tenant_id.tenant_id,
        name=tenant.name.name,
        status=tenant.status.value,
        state=tenant.state.value,
        version=tenant.version.version,
    )


# from_dto — из port-level TenantVersionDTO
from datetime import datetime

from application.ports.repositories.tenant import TenantVersionDTO


@dataclass(slots=True, frozen=True)
class TenantVersionSimpleDTO:
    tenant_id: UUID
    name: str
    status: str
    state: str
    version: int
    event: str
    editor_id: UUID | None
    created_at: datetime

    @classmethod
    def from_dto(cls, dto: TenantVersionDTO) -> Self:
        return cls(
            tenant_id=dto.tenant.tenant_id.tenant_id,
            name=dto.tenant.name.name,
            status=dto.tenant.status.value,
            state=dto.tenant.state.value,
            version=dto.tenant.version.version,
            event=dto.event.value,
            editor_id=dto.editor_id.user_id if dto.editor_id is not None else None,
            created_at=dto.created_at,
        )
```

## Naming convention

| Что описывает | Имя | Источник для фабрики | Категория |
|---|---|---|---|
| Текущее состояние одного агрегата | `<Aggregate>SimpleDTO` | `<Aggregate>` (domain) | базовое |
| Версионный снапшот одного агрегата | `<Aggregate>VersionSimpleDTO` | `<Aggregate>VersionDTO` (port-level) | базовое |
| Сценарный DTO, охватывающий несколько агрегатов | `<Scenario>DTO` (без `Simple`) | по сценарию | сценарное расширение |

**Суффикс `Simple`** маркирует **базовый** DTO:
- Базовые DTO (`Simple`) есть у каждого агрегата как минимум — описывают одну сущность плоско в примитивах.
- Набор может расширяться **сценарными DTO** под конкретный use case, который возвращает данные нескольких агрегатов сразу. У сценарных DTO суффикса `Simple` нет.
- Дополнительно `Simple` снимает коллизию имён с port-level `<Aggregate>VersionDTO` (тот живёт в `application/ports/repositories/<aggregate>.py` и держит ссылки на domain).

## Расположение и импорты

- Один файл на агрегат: `application/dto/<aggregate>.py`.
- Файл содержит все DTO агрегата (`<Aggregate>SimpleDTO`, `<Aggregate>VersionSimpleDTO`, и любые будущие сценарные).
- `application/dto/__init__.py` остаётся **пустым** — re-export DTO не делаем.
- Из use case-ов импорт прямой: `from application.dto.tenant import TenantSimpleDTO`.

## Что НЕ делаем в DTO

- Не считаем производные значения, требующие логики (`is_active`, `display_name` и т.п.). Если presentation хочет такое — он считает сам, либо это идёт в domain как метод/property и фабрика просто разворачивает.
- Не валидируем поля (валидация на входе — задача presentation; на выходе — нечего валидировать).
- Не пишем `to_dict` / `to_json` / `model_dump` — сериализация это presentation.
- Не определяем `__init__` руками — `@dataclass` его сгенерирует.
- Не используем `field(default_factory=...)` без явной необходимости — DTO собирается фабрикой `from_*`, дефолтные значения создают двусмысленность.

## Сценарные DTO

Появляются когда:
- Один use case возвращает данные **нескольких связанных агрегатов** в одном ответе.
- Базовых `Simple`-DTO недостаточно для описания результата.

Правила:
- Имя: `<Scenario>DTO` (`TenantWithUsersDTO`, `OrderFullDTO` и т.п.) — без `Simple`.
- Структура (плоская vs вложенная) — обсуждается с пользователем per scenario; скил не диктует.
- Иммутабельность та же: `@dataclass(slots=True, frozen=True)`.
- Фабрика — на усмотрение сценария (может быть `from_domain`, `from_dto`, либо специфичная `from_*`).
- Расположение: `application/dto/<aggregate>.py` (если основной агрегат сценария очевиден) или `application/dto/<scenario>.py` для подчёркнуто кросс-агрегатных.
