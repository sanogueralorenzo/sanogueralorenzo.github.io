# Assistant

![Assistant Home with Reply and Go-ahead controls](docs/assistant.jpg)

A local assistant built on Pi Durable. Home routes requests to persistent conversations; session agents can assign focused tasks to workers while continuing their own work. Workers inherit the parent's available tools, model, and working directory and choose how to complete the assignment. Delegation needs only a task. Outstanding work is collected before finishing or explicitly cancelled, including nested delegations. Conversations, child agents, queues, and streamed progress survive service restarts. The browser follows Pi’s committed conversation views; streamed text and tool output use a 16 ms commit interval. Interrupted unsafe tools are reported to the model instead of replayed.

Open `http://127.0.0.1:4180`. Reply quotes a selected message; thumbs-up sends “Yes, go ahead.” Queued messages support Edit, Delete, and Steer. Stop preserves waiting work; Continue resumes the stopped request before follow-ups. Tab accepts a saved, tool-free reply suggestion; Escape dismisses it or clears its quote.

## Start

Requires Node 26+. Click the dot, choose Sign in, API key, or Cloud, then search for a provider to connect. Sign-in opens in a browser tab; the link remains available if pop-ups are blocked. Manual code or redirect entry is available as a fallback. Select a model after connecting. The selection applies to new tasks; existing conversations keep their model.

```bash
cd tools/assistant
npm ci --ignore-scripts
npm start
```

Install Codex Computer Use in the desktop app for native app control. Assistant automatically accepts its approval requests. `service/install.sh` starts Assistant after login on macOS; `service/uninstall.sh` removes the service.

State and transcripts live in `~/.assistant/durable.sqlite`; suggestions live in `~/.assistant/suggestions.db`. Provider credentials stay in `~/.assistant/auth.json`, with the selected provider and model in `~/.assistant/provider.json`. Pi manages the installation ID in `~/.assistant/settings.json`.

Run `npm run check`. The [instruction benchmark](evals/benchmark/README.md) uses Durable for native agent integration. `npm run eval:suggestions` runs the tool-free suggestion trials with the saved Codex login.

## Headless

On a headless Linux host with Node 26+, run the start commands above. From your laptop, forward the web UI and OpenAI's callback port:

```bash
ssh -N -L 4181:127.0.0.1:4180 -L 1455:127.0.0.1:1455 user@pi-host
```

Open `http://127.0.0.1:4181` on your laptop and sign in there. Port 1455 must be free on your laptop; forwarding it lets OpenAI return to Assistant on the host automatically. Without that forward, finish browser sign-in and paste the final redirect URL into Assistant's manual fallback. API keys need no browser callback.

The service installer is macOS-only. Codex Computer Use requires the desktop plugin; it is unavailable on a headless Raspberry Pi. Coding and shell tools run on the host.
