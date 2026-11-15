# Browser Hooks

Small hooks that run inside websites you are already signed into. No browser
profile extraction, Keychain access, Slack app, or OAuth setup.

## Slack proof of concept

Open your self-DM in Slack in Edge. In Developer Tools → Sources → Snippets,
create a snippet with [slack/hook.js](slack/hook.js), then run it. Send
`hook ping` to yourself; the hook replies in that message's thread as you.

The page shows a small status control. Click **Stop**, run
`agentHooks.stop()`, or reload the tab to stop. `agentHooks.status()` returns
connection state and message counts, without credentials.

By default the hook echoes requests. Replace its handler in the same page to
provide your own browser-based behavior:

```js
agentHooks.setHandler(async ({ text, threadTs }) => {
  return `Received in this thread: ${text}`;
});
```

Handlers receive request text and message/thread/channel identifiers, never
session credentials. Running a local coding CLI would require a separate bridge;
this proof of concept runs entirely in the browser.

The hook accepts only new `hook ` messages from you in your self-DM and keeps
replies in their threads. Other conversations cannot trigger it. Per-thread
queues and message IDs prevent overlapping runs and repeated event replies.

Keep the Slack tab open. Hooks stop on reload; reconnects do not replay missed
messages. Slack's web authentication and event protocol are unofficial and may
change. Credentials stay within the signed-in page; no IDs, sessions, or secrets
belong in this folder.

Checks: `node --test slack/hook.test.mjs` from this directory.
