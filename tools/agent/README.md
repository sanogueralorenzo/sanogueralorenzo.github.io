# Agent

![Agent — focused agents route, organize, and execute work in one workflow](docs/banner.png)

A local assistant that divides work among focused agents. Routing finds the right conversation, dispatch handles dependencies, and a coordinator delegates focused tasks to workers.

Independent tasks run in parallel. Follow-ups wait for the results they need. Conversations and task progress survive restarts.

Workers can research the web, write code, run commands, and interact with apps. You follow progress and receive answers in one conversation.

**Start** (Node 26+):

```bash
cd tools/agent
npm ci --ignore-scripts
npm start
```

Open `http://127.0.0.1:4180`, click the status dot, and connect a provider using Sign in, API key, or Cloud.

For native app control, install Codex Computer Use in the desktop app. On macOS, `service/install.sh` starts Agent after login; `service/uninstall.sh` removes the service.

[Usage](docs/usage.md) · [Headless setup](docs/headless.md) · [Development](docs/development.md)
