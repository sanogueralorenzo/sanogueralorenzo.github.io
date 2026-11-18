# Usage

Open `http://127.0.0.1:4180`. Send a message from Home to start or continue a conversation, or send it inside a conversation to bypass routing. With no saved conversations, the first Home message starts a session immediately.

Independent requests can run concurrently in one conversation. Follow-ups that need earlier results wait for those tasks. Research, implementation, and review are examples of focused worker assignments, not fixed stages.

## Conversation controls

- **Reply** quotes a selected message; thumbs-up sends “Yes, go ahead.”
- Dependent messages show what they are waiting for and support **Edit**, **Delete**, and **Steer**. Corrections replace their target task and redirect waiting dependents; cancellation stops the selected task.
- **Stop** preserves waiting work. **Continue** resumes the stopped request before follow-ups.
- Drafts are saved per conversation across replies, navigation, and reconnects. **Tab** accepts a saved, tool-free reply suggestion; **Escape** dismisses it or clears its quote.

Ask to switch folders within a conversation. Agent validates and saves the directory and loads its instructions and skills. Existing workers keep their directories; new workers inherit the updated one.

Conversations and workers use provider-hosted web search first. Browser interaction is a fallback for inaccessible content, authenticated sites, or tasks that require interaction. Native app control requires Codex Computer Use in the desktop app; Agent automatically accepts its approval requests.

## Providers

Click the status dot, choose **Sign in**, **API key**, or **Cloud**, then search for a provider. Sign-in opens a browser tab; the link stays available if pop-ups are blocked. Browser logins finish through Pi's callback listener, with code entry when required by the provider.

Click a connected provider to select a model or disconnect. The selection applies to new tasks; existing conversations keep their model.

Connected OpenAI, Anthropic, xAI, and Google accounts show a lightning button for fast mode. It starts off and costs more. Changes apply to existing conversations and reply suggestions on their next request; model compatibility is handled automatically. Gemini priority requires an eligible paid account; older Claude Opus previews require fast-mode access.
