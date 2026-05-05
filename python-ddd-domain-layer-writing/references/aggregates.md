# Aggregates

## Базовые классы `Entity` и `EntityWithState`

### Назначение

Базовые классы инкапсулируют то, что должно быть одинаковым для всех агрегатов:
- Версионирование с поддержкой оптимистичного параллелизма (`version` / `original_version` / `mark_persisted` / `_update_version`).
- Контракт построения payload-а доменной ошибки (`_error_data`).
- Отладочное представление (`__repr__`).
- Стандартный набор методов состояния для агрегатов с двумя состояниями (`activate` / `delete` / `new_state` / `_check_state`).

Живут в `domain/entities.py`. Других классов в этом файле быть не должно.

### Реализация

```python
from abc import ABC, abstractmethod
from typing import Any, ClassVar

from domain.errors import EntityIdempotentError, EntityInvalidDataError
from domain.value_objects import AggregateName, State, Version


class Entity(ABC):
    def __init__(
        self,
        version: Version,
        aggregate_name: AggregateName,
    ) -> None:
        self._version = version
        self._original_version = version
        self._aggregate_name = aggregate_name

    @property
    def version(self) -> Version:
        return self._version

    @property
    def original_version(self) -> Version:
        return self._original_version

    @property
    def aggregate_name(self) -> AggregateName:
        return self._aggregate_name

    def mark_persisted(self) -> None:
        self._original_version = self._version

    def _update_version(self) -> None:
        if self._version == self._original_version:
            self._version = Version(self._original_version.version + 1)

    @abstractmethod
    def _error_data(
        self,
        msg: str,
        data: dict[str, Any] | None = None,
    ) -> dict[str, Any]: ...

    def __repr__(self) -> str:
        fields = ", ".join(f"{k}={v!r}" for k, v in vars(self).items())
        return f"{self.__class__.__name__}({fields})"


class EntityWithState(Entity):
    _DELETED_MSG: ClassVar[str] = "сущность удалена, операция запрещена"

    def __init__(
        self,
        state: State,
        version: Version,
        aggregate_name: AggregateName,
    ) -> None:
        super().__init__(version=version, aggregate_name=aggregate_name)
        self._state = state

    @property
    def state(self) -> State:
        return self._state

    def new_state(self, state: State) -> None:
        if self._state == state:
            raise EntityIdempotentError(
                **self._error_data(
                    msg="новое состояние идентично текущему",
                    data={"state": state.value},
                )
            )
        self._state = state
        self._update_version()

    def activate(self) -> None:
        if self._state.is_active():
            raise EntityIdempotentError(
                **self._error_data(
                    msg=f"{self._aggregate_name.name} уже активно",
                    data={"state": self._state.value},
                )
            )
        self._state = State.ACTIVE
        self._update_version()

    def delete(self) -> None:
        if self._state.is_deleted():
            raise EntityIdempotentError(
                **self._error_data(
                    msg=f"{self._aggregate_name.name} уже удалено",
                    data={"state": self._state.value},
                )
            )
        self._state = State.DELETED
        self._update_version()

    def _check_state(self, data: dict[str, Any] | None = None) -> None:
        if self._state.is_deleted():
            data = data or {}
            data["state"] = self._state.value
            raise EntityInvalidDataError(**self._error_data(self._DELETED_MSG, data))
```

### Цикл версионирования

```
new()                    →  version=1, original_version=1
первая мутация           →  version=2, original_version=1   (помечен «грязным»)
повторные мутации        →  version=2, original_version=1   (не инкрементятся)
mark_persisted()         →  version=2, original_version=2   (синхронизация после save)
следующая мутация        →  version=3, original_version=2
```

**Логика `_update_version`** — инкрементирует только если `version == original_version`. То есть в одной «сессии работы с агрегатом» (между двумя `mark_persisted`) версия растёт максимум на 1. Это правильно: оптимистичный параллелизм работает на уровне «эта сессия кончится сохранением версии N+1», а не «сколько раз вызвали мутаторы».

**`mark_persisted` вызывает не агрегат и не сервис, а репозиторий** — после успешного INSERT/UPDATE.

**Пара `version` / `original_version` нужна репозиторию для:**
- `INSERT` — берёт `version` (новое значение).
- `UPDATE ... WHERE version = original_version` — оптимистичная блокировка.

### Контракт `_error_data`

Метод абстрактный — каждый агрегат реализует его, описывая свой ID и ключ верхнего уровня в `data`. Возвращает `dict`, который раскрывается в kwargs доменной ошибки.

```python
class PersonalTransaction(EntityWithState):
    def _error_data(
        self,
        msg: str,
        data: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        data = data or {}
        data["transaction_id"] = self._transaction_id.transaction_id
        return {
            "msg": msg,
            "subject": self._aggregate_name.name,
            "data": {"transaction": data},
        }
```

**Правила:**
- Всегда добавляет `<aggregate>_id` в `data` — это делает все ошибки агрегата трассируемыми.
- ID в виде сырого `UUID` (не `<Aggregate>ID`-VO) — `data` идёт в JSON-сериализацию.
- Ключ верхнего уровня `data` — английское имя агрегата в единственном числе (`transaction`, `category`, `tenant`).
- `subject` = `self._aggregate_name.name` — на языке домена.

### `__repr__` через `vars(self)`

`__repr__` базы автоматически перечисляет все атрибуты экземпляра. Подкласс ничего не настраивает. `__str__` не определяем — `object.__str__` сам делегирует к `__repr__`.

### Паттерн `_check_state` через `_DELETED_MSG`

`EntityWithState._check_state(data)` проверяет только `is_deleted` — это самый частый guard для мутирующих методов. Сообщение per-aggregate декларируется через приватный `ClassVar`:

```python
class PersonalTransaction(EntityWithState):
    _DELETED_MSG: ClassVar[str] = "транзакция была удалена, ее редактирование запрещено"
```

**Почему `ClassVar` лучше override `_check_state`:**
- Сигнатура `_check_state` одна и та же на всех уровнях (нет LSP-нарушений).
- Сообщение — данные, не поведение; читается как поле, а не как метод.
- Не требует знаний `super()`-цепочки в подклассе.

### Стандартные методы `EntityWithState`

| Метод | Что делает | Когда использовать в use case |
|---|---|---|
| `new_state(state)` | Меняет состояние на любое; идемпотентность по `==`; не проверяет переходы | Синхронизация состояния от внешнего источника, не команды пользователя |
| `activate()` | Устанавливает `ACTIVE`; идемпотентность если уже `ACTIVE` | Восстановление удалённой записи |
| `delete()` | Устанавливает `DELETED`; идемпотентность если уже `DELETED` | Soft-delete команда |
| `_check_state(data=None)` | Бросает `EntityInvalidDataError` с `_DELETED_MSG`, если удалён | В первой строке любого мутирующего метода (кроме самих state-changing) |

**Важно:** `activate` / `delete` / `new_state` сами `_check_state` **НЕ зовут** — они и есть смена состояния, проверять нечего.

## Класс агрегата

### Структура файла и класса

- Один агрегат на файл — `domain/<aggregate_name>/entity.py`.
- Файл содержит **только** класс агрегата и нужные импорты. Никаких free-functions, helpers, фабрик в этом же файле.
- Класс наследуется от `EntityWithState` (для двух стандартных состояний) либо от `Entity` напрямую (для расширенного state).
- Имя класса — существительное в единственном числе, PascalCase.

### Конструктор

**Порядок параметров:**
1. Идентификатор агрегата (`<Aggregate>ID`).
2. Ссылки на другие агрегаты (через их ID).
3. Атрибуты — VO в порядке бизнес-значимости.
4. Системные поля в конце: `state`, `version`.

**Принципы:**
- Параметры — **только VO**. Никаких `str`, `UUID`, `Decimal`, `datetime` напрямую — приведение примитивов к VO делает фабрика.
- Тело конструктора: вызов `super().__init__(...)` с системными полями, далее присваивание приватных полей.
- Все имена приватных полей соответствуют именам параметров с префиксом `_`.

```python
class PersonalTransaction(EntityWithState):
    _DELETED_MSG: ClassVar[str] = "транзакция была удалена, ее редактирование запрещено"

    def __init__(
        self,
        transaction_id: PersonalTransactionID,
        category_ids: set[TransactionCategoryID],
        owner_id: TenantID,
        name: PersonalTransactionName,
        description: PersonalTransactionDescription,
        transaction_type: PersonalTransactionType,
        money_amount: MoneyAmount,
        transaction_time: PersonalTransactionTime,
        state: State,
        version: Version,
    ) -> None:
        super().__init__(
            state=state,
            version=version,
            aggregate_name=AggregateName("персональная транзакция"),
        )
        self._transaction_id = transaction_id
        self._category_ids = category_ids
        self._owner_id = owner_id
        self._name = name
        self._description = description
        self._transaction_type = transaction_type
        self._money_amount = money_amount
        self._transaction_time = transaction_time
```

### Properties — публичный read-доступ

Все приватные поля экспонируются через `@property` без сеттера:

```python
@property
def transaction_id(self) -> PersonalTransactionID:
    return self._transaction_id

@property
def name(self) -> PersonalTransactionName:
    return self._name
```

**Правила:**
- Имя property = имя поля без `_`.
- Возвращаем VO, не примитив — клиент сам достанет нужное (`transaction.name.name`).
- Никогда не возвращаем копию изменяемой коллекции — возвращаем сам `set`/`list`. Защита от внешней мутации обеспечивается культурой, а не оборонительным копированием.
- `version` / `original_version` / `aggregate_name` / `state` уже определены в базе — не переопределяем.

### Канонический шаблон метода-мутатора

Любой метод, изменяющий поле агрегата, следует одной структуре:

```python
def new_name(self, name: PersonalTransactionName) -> None:
    self._check_state()                                       # 1
    if self._name == name:                                     # 2
        raise EntityIdempotentError(
            **self._error_data(
                msg="название транзакции идентично текущему названию",
                data={"name": name.name},
            )
        )
    self._name = name                                          # 3
    self._update_version()                                     # 4
```

**Пошагово:**

1. **`self._check_state()`** — guard от мутации удалённой сущности. Бросит `EntityInvalidDataError` с `_DELETED_MSG`. **Не зовётся** в самих state-changing методах.

2. **Идемпотентность через `==`** — сравнение нового и текущего значения. Если совпадает — `EntityIdempotentError`.

3. **Мутация** — присваивание приватного поля.

4. **`self._update_version()`** — инкремент версии. Только после реальной мутации.

**Сигнатура:** возвращает `None`, мутация in-place. Не возвращаем новый агрегат и не возвращаем сам себя для chaining.

**Имя метода:** `new_<field>` для замены значения (`new_name`, `new_description`, `new_money_amount`). Для коллекций — операционные глаголы (`add_categories`, `remove_categories`).

### Bulk-операции на коллекциях

```python
def add_categories(self, categories: set[TransactionCategory]) -> None:
    self._check_state()
    if len(categories) == 0:
        raise EntityInvalidDataError(
            **self._error_data(msg="не переданы категории для добавления")
        )
    self.validate_categories(categories)

    already_present = {c for c in categories if c.category_id in self._category_ids}
    if already_present and len(already_present) == len(categories):
        raise EntityInvalidDataError(
            **self._error_data(
                msg="все переданные категории уже присвоены транзакции",
                data={
                    "categories": [
                        {"category_id": c.category_id.category_id, "name": c.name.name}
                        for c in categories
                    ],
                },
            )
        )

    self._category_ids.update(c.category_id for c in categories)
    self._update_version()
```

**Принципы для bulk-методов:**
- Пустая коллекция на входе — `EntityInvalidDataError`, не no-op.
- Если **все** элементы избыточны (уже есть при `add` или отсутствуют при `remove`) — `EntityInvalidDataError`. Если избыточна **часть** — обрабатываем оставшиеся и инкрементим версию.
- Кросс-агрегатная валидация (`validate_categories`) — до проверки избыточности.

### Кросс-агрегатные ссылки

**Главное правило:** агрегат хранит ссылки на другие агрегаты только через их ID, никогда не как объект целиком.

```python
self._owner_id: TenantID                          # правильно
self._category_ids: set[TransactionCategoryID]    # правильно
self._owner: Tenant                                # запрещено
self._categories: set[TransactionCategory]         # запрещено
```

**Когда метод агрегата принимает full-объект другого агрегата:**

Если для валидации нужно прочитать поля другого агрегата (например, его `state`, `owner_id`), метод **принимает full-объект, но сохраняет только его ID**:

```python
def new_categories(self, categories: set[TransactionCategory]) -> None:
    self._check_state()
    self.validate_categories(categories)              # читает category.state, category.owner_id
    if self._category_ids == {c.category_id for c in categories}:
        raise EntityInvalidDataError(...)
    self._category_ids = {c.category_id for c in categories}   # храним только ID
    self._update_version()
```

**Полные объекты получает use case из репозитория и передаёт в метод агрегата.** Сам агрегат не вытаскивает их через сервисы или репозитории — он не знает о существовании этих абстракций.

### Публичные методы валидации без мутации

Иногда логика валидации другого агрегата нужна **до** создания текущего. В этом случае агрегат публикует валидатор как публичный метод (без `_`), не привязанный к мутации:

```python
def validate_categories(self, categories: set[TransactionCategory]) -> None:
    self._validate_category_owners(categories)
    self._validate_deleted_categories(categories)

def _validate_category_owners(self, categories: set[TransactionCategory]) -> None:
    invalid = [c for c in categories if self._owner_id != c.owner_id]
    if invalid:
        raise EntityInvalidDataError(
            msg="чужие категории нельзя назначить транзакции",
            subject=next(iter(categories)).aggregate_name.name,
            data={
                "categories": [
                    {"category_id": c.category_id.category_id} for c in invalid
                ],
            },
        )
```

**Конвенция:**
- Имя начинается с `validate_` — сигнализирует «нет мутации, может бросить ошибку».
- Использует `subject` другого агрегата (не своего), потому что ошибка про их данные.
- Декомпозируется на приватные `_validate_*` методы по одному инварианту.

### Методы-предикаты для policy-проверок

Если агрегат участвует в политиках, методы именуются `raise_<policy>` и бросают `EntityPolicyError`:

```python
def raise_access_edit(self) -> None:
    self.raise_access_read()
    if self._state.is_frozen():
        raise EntityPolicyError(
            **self._error_data(
                msg="вы заморожены",
                data={"state": self._state.value},
            )
        )
```

**Конвенция:** возвращают `None` при успехе, бросают `EntityPolicyError` при нарушении. **Не** возвращают `bool`.

## Особый случай — агрегат с расширенным состоянием

Если у агрегата состояний больше двух (например, `Tenant` имеет `ACTIVE` / `FROZEN` / `DELETED`):

- Создаём свой enum в `domain/<aggregate>/value_objects.py` (`TenantState`).
- Класс наследует **`Entity`**, не `EntityWithState`.
- Реализуем переходы (`activate`, `freeze`, `delete`, `new_state`) самостоятельно — каждый с проверкой идемпотентности и `_update_version`.
- Реализуем свой `_check_state(data=None)` — он проверяет все «нерабочие» состояния (`is_deleted`, `is_frozen`).
- Заводим столько `_*_MSG` `ClassVar`, сколько состояний нужно различать.

```python
class Tenant(Entity):
    _DELETED_MSG: ClassVar[str] = "арендатор удален"
    _FROZEN_MSG: ClassVar[str] = "арендатор заморожен"

    def __init__(
        self,
        tenant_id: TenantID,
        status: TenantStatus,
        state: TenantState,
        version: Version,
    ) -> None:
        super().__init__(version=version, aggregate_name=AggregateName("арендатор"))
        self._tenant_id = tenant_id
        self._status = status
        self._state = state

    def freeze(self) -> None:
        if self._state.is_frozen():
            raise EntityIdempotentError(
                **self._error_data(
                    msg="арендатор уже заморожен",
                    data={"state": self._state.value},
                )
            )
        self._state = TenantState.FROZEN
        self._update_version()

    def _check_state(self, data: dict[str, Any] | None = None) -> None:
        data = data or {}
        data["state"] = self._state.value
        if self._state.is_deleted():
            raise EntityInvalidDataError(**self._error_data(self._DELETED_MSG, data))
        if self._state.is_frozen():
            raise EntityInvalidDataError(**self._error_data(self._FROZEN_MSG, data))

    def _error_data(self, msg: str, data: dict[str, Any] | None = None) -> dict[str, Any]:
        data = data or {}
        data["tenant_id"] = self._tenant_id.tenant_id
        return {
            "msg": msg,
            "subject": self._aggregate_name.name,
            "data": {"tenant": data},
        }
```

## Фабрика агрегата

### Назначение и структура класса

Фабрика — единственное место, где примитивные значения (`UUID`, `str`, `Decimal`, `datetime`, `int`) превращаются в Value Objects и собираются в агрегат. Назначение:

- Изолировать слой выше (use case, события) от знания о VO-обёртках и инвариантах.
- Зафиксировать дефолты момента создания (`State.ACTIVE`, `Version(1)`, бизнес-стартовый `status` и т.п.).

Расположение: `domain/<aggregate>/factory.py`. По одной фабрике на агрегат.

- Имя класса — `<Aggregate>Factory`.
- Все методы — `@staticmethod`. У фабрики нет состояния, нет зависимостей, нет наследования.
- Никаких `__init__`, никаких полей класса, никаких instance-методов.

### Метод `new()`

**Назначение:** создание агрегата при первичном появлении (команда «создать»).

**Сигнатура:**
- Принимает только те примитивы, которые передаёт бизнес-источник.
- НЕ принимает `state`, `version` — это управляемые дефолты.
- НЕ принимает поля, которые задаются бизнес-правилом «новый агрегат всегда такой».

**Реализация:**
- Конвертирует все примитивы в VO.
- Передаёт в конструктор агрегата `state=State.ACTIVE` и `version=Version(1)`.
- Захардкоживает «business-defaults» — стартовые значения, диктуемые бизнесом.

```python
class PersonalTransactionFactory:
    @staticmethod
    def new(
        transaction_id: UUID,
        category_ids: set[UUID],
        owner_id: UUID,
        name: str,
        description: str,
        transaction_type: str,
        amount: Decimal,
        currency: str,
        transaction_time: datetime,
    ) -> PersonalTransaction:
        return PersonalTransaction(
            transaction_id=PersonalTransactionID(transaction_id),
            category_ids={TransactionCategoryID(cid) for cid in category_ids},
            owner_id=TenantID(owner_id),
            name=PersonalTransactionName(name),
            description=PersonalTransactionDescription(description),
            transaction_type=PersonalTransactionType.from_str(transaction_type),
            money_amount=MoneyAmount(
                amount=amount,
                currency=Currency.from_str(currency),
            ),
            transaction_time=PersonalTransactionTime(transaction_time),
            state=State.ACTIVE,
            version=Version(1),
        )
```

**Пример с business-default:**

```python
class TenantFactory:
    @staticmethod
    def new(tenant_id: UUID, state: str) -> Tenant:
        return Tenant(
            tenant_id=TenantID(tenant_id),
            status=TenantStatus.TENANT,                       # business default
            state=TenantState.from_str(state),
            version=Version(1),
        )
```

`status` в `new()` — не параметр. Если завтра потребуется создать админа — это **другой** сценарий и **другой** метод.

### Метод `restore()`

**Назначение:** восстановление агрегата из персистентного хранилища или другого внешнего источника.

**Сигнатура:**
- Принимает **все** поля агрегата как примитивы — включая `state` и `version`.
- Никаких дефолтов нет: агрегат может быть в любом валидном состоянии.

```python
class PersonalTransactionFactory:
    @staticmethod
    def restore(
        transaction_id: UUID,
        owner_id: UUID,
        name: str,
        description: str,
        category_ids: set[UUID],
        transaction_type: str,
        amount: Decimal,
        currency: str,
        transaction_time: datetime,
        state: str,
        version: int,
    ) -> PersonalTransaction:
        return PersonalTransaction(
            transaction_id=PersonalTransactionID(transaction_id),
            category_ids={TransactionCategoryID(cid) for cid in category_ids},
            owner_id=TenantID(owner_id),
            name=PersonalTransactionName(name),
            description=PersonalTransactionDescription(description),
            transaction_type=PersonalTransactionType.from_str(transaction_type),
            money_amount=MoneyAmount(
                amount=amount,
                currency=Currency.from_str(currency),
            ),
            transaction_time=PersonalTransactionTime(transaction_time),
            state=State.from_str(state),
            version=Version(version),
        )
```

**Кто вызывает `restore`:** только репозитории. Use case никогда не зовёт `restore` напрямую.

### Где живёт генерация ID

ID для нового агрегата генерируется не в фабрике, а в **репозитории** через метод `next_id()`. Use case делает примерно так:

```python
async with self._uow as uow:
    transaction_id = await uow.transaction_repositories.read.next_id()
    transaction = PersonalTransactionFactory.new(
        transaction_id=transaction_id.transaction_id,
        ...
    )
```

**Почему не в фабрике:**
- Генерация ID — деталь персистентности (UUIDv7 c источником времени, БД-секвенс, snowflake и т.п.). Фабрика остаётся чистой.
- Фабрика синхронная и без зависимостей — `await uuid7()` или похожее в неё не помещается.

### Конвертация примитивов в VO

Внутри фабрики **каждый** примитив проходит через свою VO-обёртку:

| Примитив | Конвертация |
|---|---|
| `UUID` | `<Aggregate>ID(value)` |
| `str` для именованного поля | `<Field>VO(value)` (валидация в `__post_init__`) |
| `str` для enum-поля | `<Enum>.from_str(value)` |
| `Decimal` + `str` (валюта) | сборка нескольких VO внутрь composite-VO (`MoneyAmount`) |
| `datetime` | `<Time>VO(value)` |
| `set[UUID]` | `{<ID-VO>(v) for v in value}` |
| `int` для версии | `Version(value)` |
| `str` для состояния | `<StateEnum>.from_str(value)` |

Если на входе невалидные данные — VO сами бросят `ValueObjectInvalidDataError`. Фабрика никаких ошибок не бросает и не ловит.

## Чек-лист добавления нового метода-мутатора в агрегат

1. Имя — `new_<field>` или операционный глагол.
2. Параметры — VO, не примитивы.
3. Возврат — `None`, мутация in-place.
4. **Первая строка** — `self._check_state()` (если не сам state-changing).
5. **Вторая строка** — проверка идемпотентности через `==`.
6. **Третья** — мутация поля.
7. **Четвёртая** — `self._update_version()`.

## Анти-паттерны

❌ **Property с setter-ом.** Все мутации — через именованные методы.

❌ **Параметры конструктора как примитивы.** Только VO. Если в сигнатуре `name: str` — это работа фабрики.

❌ **Возврат `self` или нового агрегата из мутатора.** Мутация in-place, возврат — `None`. Никакого method chaining.

❌ **Передача по ссылке полного агрегата для хранения.** `self._owner: Tenant` — **запрещено**. Только `self._owner_id: TenantID`.

❌ **Проброс репозиториев или сервисов в агрегат.** Агрегат не знает про БД, очереди, события.

❌ **Защитное копирование коллекций в property.** Возвращаем `self._category_ids` как есть.

❌ **Метод без `_check_state` там, где он должен быть.** Если мутатор не самим состоянием — обязан проверить, что агрегат не удалён.

❌ **`_update_version` без реальной мутации.** Если метод выходит через идемпотентность или ошибку — версия не должна расти.

❌ **`_update_version` дважды в одном методе.** В каноничном шаблоне `_update_version` ровно один — в самом конце.

❌ **Метод агрегата, изменяющий несколько других агрегатов одной операцией.** Принцип «одна транзакция = один агрегат» соблюдается на уровне use case, но domain-слой обязан давать ему такую возможность. Если метод агрегата A читает агрегат B для валидации — это нормально; если он **меняет** B — это нарушение.

❌ **Параметры с `default` для бизнес-полей в `Factory.new()`.** Если у поля нет фиксированного дефолта от бизнеса — оно обязательное.

❌ **VO в сигнатуре фабрики.** Фабрика именно для того и нужна, чтобы вышестоящие слои не знали про VO.

❌ **Фабрика как instance-класс с `__init__`.** Никаких зависимостей, конфигов, DI в фабрике.

❌ **Фабрика, обращающаяся к репозиторию или сервису.** Это работа доменного сервиса, не фабрики.

❌ **`next_id()` в фабрике.** ID генерируется в репозитории.

❌ **`try/except` в фабрике вокруг конструкторов VO.** VO бросает `ValueObjectInvalidDataError` — это валидная доменная ошибка, она должна свободно подниматься.
