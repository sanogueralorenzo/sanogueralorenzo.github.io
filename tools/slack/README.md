# Agent Slack

![Agent Slack banner](docs/banner.png)

A small, self-hosted bridge from Slack to your coding tools. Run it on your laptop or in the cloud, using the repos, commands, and settings you choose.

**Install or update** from the latest `main` (macOS or Linux with systemd, Git, and an authenticated coding CLI):

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/slack/install.sh | sh
```

The installer downloads a private Python runtime, configures the installed Codex/Claude wrappers, guides you through [Slack approval and tokens](docs/slack.md), and starts a background service. Rerun it after approval if needed. Updates preserve your configuration and sessions.

**`chat investigate project`** runs Codex in `project`; **`claude review service`** runs Claude in `service`. Add aliases in `~/.local/share/agent-slack/.env`. The first alias mentioned selects the directory; without one, a new thread uses the configured default workspace and a follow-up keeps its previous directory.

Only your messages trigger work; answers appear in the same thread. Start each request with a configured keyword, ignoring case (`chat`, `Chat`, and `CHAT` all work). Follow-ups in the same thread resume its session with new context. Changing commands or directories starts fresh. Up to eight threads run at once; requests within a thread run in order.

**👀** queued or running · **✅** answered · **🤖** AI reply. Failure removes 👀 and logs the error locally.

State stays in `~/.local/state/agent-slack`. Rerun the installer after editing `.env`; it must have permissions `600`. Service controls and logs are in [Slack setup](docs/slack.md).

Local development (Python 3.10+):

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e .
cp .env.example .env
chmod 600 .env
# Edit .env with your tokens and workspaces.
agent-slack
```

Source lives in `src/agent_slack`; tests live in `tests`. Run checks with `python -m unittest discover -s tests`. `python -m agent_slack` also starts the bridge; use `--config /path/to/.env` from another directory. Environment variables override file values. Custom commands: [command wrappers](docs/commands.md).
