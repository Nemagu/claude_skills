# Retry and DLQ Strategy

## Error Classes

- `RetriableError`: сетевые сбои, временная недоступность, таймауты.
- `TerminalError`: невалидный payload, нарушение доменного контракта, unsupported version.

## Retry Model

- Ограничивай количество доставок через `max_deliver`.
- Используй backoff-политику, если она поддерживается клиентом и топологией.
- Логируй номер попытки и причину повторной обработки.

## DLQ Routing

- Отправляй терминальные сообщения в отдельный subject.
- Добавляй metadata: original subject, timestamp, exception class, attempt.
- Не теряй исходный payload и event_id.

## Operational Rules

- Делай алерт на рост DLQ и превышение retry threshold.
- Периодически анализируй DLQ для обратной связи в schema и код.
