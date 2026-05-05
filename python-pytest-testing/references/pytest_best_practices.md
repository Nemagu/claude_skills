# Pytest Best Practices

## Arrange-Act-Assert

- Структурируй тест по блокам Arrange, Act, Assert.
- Держи один поведенческий контракт на тест, чтобы падение было диагностируемым.

## Parametrize Pattern

```python
import pytest

@pytest.mark.parametrize(
    "raw,expected",
    [
        ("  Alice ", "Alice"),
        ("Bob", "Bob"),
        ("", ""),
    ],
    ids=["trim-spaces", "already-clean", "empty"],
)
def test_normalize_name(raw: str, expected: str) -> None:
    assert normalize_name(raw) == expected
```

## Fixtures

- Фикстура возвращает готовый объект, а не выполняет лишнюю бизнес-логику.
- Избегай autouse-фикстур без необходимости; они скрывают зависимости теста.
- Используй `scope` осознанно: `function` по умолчанию, расширяй только при измеримой пользе.

## Anti-Patterns

- Проверка нескольких независимых контрактов в одном тесте.
- Неявные зависимости через глобальное состояние.
- Ассерты по внутренним деталям вместо наблюдаемого поведения.
- Тесты, чувствительные к порядку запуска.
