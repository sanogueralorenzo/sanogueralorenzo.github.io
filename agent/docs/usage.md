# Usage

Open `http://127.0.0.1:4180` or run `npm run terminal` from `agent`. Send a message from Home to start or continue a conversation, or send it inside a conversation to bypass routing. With no saved conversations, the first Home message starts a session immediately.

Independent requests can run concurrently in one conversation. Follow-ups that need earlier results wait for those tasks. Research, implementation, and review are examples of focused worker assignments, not fixed stages.

## Conversation controls

- **Reply** quotes a selected message; thumbs-up sends “Yes, go ahead.”
- Dependent messages show what they are waiting for and support **Edit**, **Delete**, and **Steer**. Corrections replace their target task and redirect waiting dependents; cancellation stops the selected task.
- **Stop** preserves waiting work. **Continue** resumes the stopped request before follow-ups.
- Drafts are saved per conversation across replies, navigation, and reconnects. **Tab** accepts a saved, tool-free reply suggestion; **Escape** dismisses it or clears its quote.

Ask to switch folders within a conversation. Agent validates and saves the directory and loads its instructions and skills. Existing workers keep their directories; new workers inherit the updated one.

Conversations and workers use provider-hosted web search first. Browser interaction is a fallback for inaccessible content, authenticated sites, or tasks that require interaction. Native app control requires Codex Computer Use in the desktop app; Agent automatically accepts its approval requests.

## Terminal

**Enter** sends from the composer or opens a focused conversation from Home. You can also double-click a Home message to open its conversation. **Tab** moves focus. Click a message and type to quote it. Press **y** on a selected Agent reply to send a thumbs-up, or **Tab** first to type a reply starting with **y**.

**Esc** clears the selection or quote, then goes Home. Running work continues when you leave. Open the conversation to **Stop** or **Continue** work. **Shift+Enter** or **Ctrl+J** inserts a new line. **Ctrl+C** quits.

Use the web client to manage the queue, steer work, change providers, or use reply suggestions. Set `AGENT_URL` to connect to another address, such as an SSH-forwarded port. Terminal drafts stay local to the client.

## Providers

Open Accounts to see Codex, Claude Code, and Google Antigravity. A provider is green when its official CLI is installed and authenticated on the Agent host. The main dot is green when at least one provider is connected.

Sign in from the host terminal with `codex login`, `claude auth login`, or `agy acp --login`. Click a connected provider to select a model for new conversations. Existing conversations keep their model while its CLI is connected and use an available provider if it disconnects.

The lightning button enables fast mode for Codex and supported Claude models. It starts off and can increase usage cost.
