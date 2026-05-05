# Handler Pipeline Template

```python
async def handle_message(msg: Msg) -> None:
    envelope = decode_message(msg)
    validate_envelope(envelope)

    if await is_duplicate(envelope.event_id):
        await msg.ack()
        return

    try:
        await run_use_case(envelope.payload)
    except RetriableError:
        await msg.nak()
        return
    except TerminalError:
        await publish_to_dlq(envelope)
        await msg.ack()
        return

    await mark_processed(envelope.event_id)
    await msg.ack()
```

## Notes

- Фиксируй dedup до или сразу после успешного side effect в зависимости от гарантии exactly-once модели.
- Не подтверждай сообщение до завершения критической бизнес-операции.
- Для terminal ошибок не оставляй сообщение бесконечно переобрабатываться.
