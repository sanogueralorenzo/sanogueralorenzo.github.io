# Slack setup

The installer opens a [prefilled Slack app creation link](https://docs.slack.dev/app-manifests/configuring-apps-with-app-manifests/#sharing-manifests) using the packaged [manifest.json](../src/agent_slack/manifest.json). Choose your workspace and create the app. If your workspace requires approval, request it under **OAuth & Permissions**.

After approval:

1. Under **Basic Information → App-Level Tokens**, create a token with `connections:write`. Copy its `xapp-` value.
2. Under **OAuth & Permissions**, install the app as your own user. Copy the **User OAuth Token** (`xoxp-`).
3. Paste both tokens into the installer's hidden prompts. If you exited while waiting for approval, rerun the same install command. Your Slack member ID is detected automatically.

The app receives your channel, DM, and group DM messages and posts replies as you. No bot token is needed. Remove unused conversation types and matching history scopes from the manifest before creating the app. For an existing app, update its manifest and reinstall after scope changes; the installer checks that your user token has the required scopes.

## Installed service

Configuration is in `~/.local/share/agent-slack/.env`. The default workspace is your home directory; add project aliases there. Rerun the installer to update or restart the service. Configuration and sessions are preserved. Keep custom wrappers outside the managed installation directory.

On macOS, Agent Slack starts at login. Logs are in `~/.local/state/agent-slack/agent-slack.log`. To stop it:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/dev.sanogueralorenzo.agent-slack.plist
```

On Linux, a systemd user session is required. Logs are available with `journalctl --user -u dev.sanogueralorenzo.agent-slack.service`. To stop it:

```sh
systemctl --user stop dev.sanogueralorenzo.agent-slack.service
```

The Linux installer also enables user lingering to keep the service running after logout. If your server requires administrator approval for that, it prints the command to request. Stop any manually launched `agent-slack` instance before installing the background service.
