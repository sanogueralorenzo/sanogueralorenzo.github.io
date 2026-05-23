# Hook Loop Example

This example shows Precedent acting as a passive hook layer during a normal agent conversation.

It runs JSON hook events through the local CLI against a temporary state directory:

1. `context.before_turn` asks for relevant precedent before the first webhook task.
2. No precedent exists yet, so nothing is injected.
3. `conversation.observe` ingests a failed webhook turn and promotes one repo-specific precedent.
4. `context.before_turn` asks again before a follow-up webhook task.
5. The webhook precedent is injected.
6. `conversation.observe` records the improved follow-up turn.
7. `report` shows the local ledger.

Run it from the repository root:

```shell
node precedent/examples/hook-loop/run.mjs
```

Expected behavior:

- The first hook returns an empty `contextBlock`.
- The second hook injects `prec_webhook_provider_boundary` in `contextBlock`.
- The final report shows one promoted precedent and four events: two hook checks plus two observed traces.
