# Assistant

![Assistant Home with Reply and Go-ahead controls](docs/assistant.jpg)

Assistant is a local assistant built on Pi. Home routes new requests and follow-ups to persistent session agents, which can delegate read-only research or review. Its Node service keeps conversations and queued work running when the browser closes. Open `http://127.0.0.1:4180`.

Hover over an assistant reply on Home or inside a session. Reply quotes that specific message as context; thumbs-up sends “Yes, go ahead.” A 👍 in the hover controls confirms it was sent. Controls are also available on keyboard focus and touch screens.

Canceling a quote keeps your draft. On Home, unquoted messages are routed automatically; inside a conversation, messages stay there with or without a quote.

Queued messages have Edit and Delete controls: hover over the message on Home, or use the queued list inside the session composer, above the input. Each queued row also has Steer while work is running: it sends that message into the active run after the current tool finishes, keeping its quote. If steering fails, the message returns to the queue. The input and its controls share the bottom row; Tab appears first when a suggestion is available, followed by Stop and Send. Edit withdraws the message and returns it to the composer, keeping its conversation and quote; sending or canceling the edit restores your previous draft. Delete removes the queued message. These controls disappear once work starts.

After each completed reply, a separate Luna 6 request generates a follow-up using only the suggestion prompt and recent conversation text, with no reasoning or tools. Results are saved per reply in `sessions.db`. Press Tab or click the Tab button to fill the draft, then Enter to send. Accepted hints quote their originating reply. Typing hides the hint; clearing both the draft and quote brings it back. Escape clears the quote and an unchanged suggested draft, restoring the visible hint; edited drafts are kept. Escape on an already empty composer hides the hint; Tab can still restore that saved suggestion. If nothing useful arrives within five seconds, the normal Message placeholder stays and Tab keeps its normal behavior.

## Start

Requires Node 26+ and a signed-in Codex CLI account in `~/.codex/auth.json`.

```bash
cd tools/assistant
npm ci
npm start
```

Install Codex Computer Use in the desktop app for native app control. Assistant automatically accepts Computer Use approval requests. Use `service/install.sh` to start Assistant after login on macOS, and `service/uninstall.sh` to remove the service. Home and session state live in `~/.assistant/sessions.db`; Pi transcripts live in `~/.assistant/sessions`.

Run `npm run check` for TypeScript and `npm test` for the focused tests.

Run `npm run eval:suggestions` for 54 tool-free baseline trials using the existing Codex login. The reusable [instruction benchmark](evals/benchmark/README.md) compares suggestions, focused agents, and skill fixtures with blinded review, outcome checks, and frozen confirmation. See its [evaluation protocol](evals/benchmark/PROTOCOL.md), [measured guidance](evals/benchmark/GUIDANCE.md), and [coverage](evals/benchmark/COVERAGE.md). Results are saved under `.precedent/assistant-benchmarks`.
