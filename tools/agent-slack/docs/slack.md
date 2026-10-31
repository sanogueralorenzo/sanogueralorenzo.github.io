# Slack setup

1. In [Slack apps](https://api.slack.com/apps), create an app from [manifest.yaml](../manifest.yaml) and select your workspace. The manifest enables Socket Mode and user message events.
2. Under **Basic Information → App-Level Tokens**, create a token with `connections:write`. Put its `xapp-` value in `.env` as `SLACK_APP_TOKEN`.
3. Under **OAuth & Permissions**, install the app as your Slack user. Put the **User OAuth Token** (`xoxp-`) in `SLACK_USER_TOKEN`, and your Slack member ID in `SLACK_USER_ID`.

For an existing app, update its manifest and reinstall after scope changes. Your workspace may require approval. Reactions require the `reactions:write` user scope.

The app receives your channel, DM, and group DM messages and posts replies as you. Remove unused conversation types and matching history scopes from the manifest before importing. No bot token is needed.

Return to [local setup](../README.md).
