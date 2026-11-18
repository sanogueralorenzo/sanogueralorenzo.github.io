# Development

Requires Python 3.10+. From `tools/slack`:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e .
cp .env.example .env
chmod 600 .env
# Edit .env with your tokens and workspaces.
agent-slack
```

Run checks with `python -m unittest discover -s tests`.

`python -m agent_slack` also starts the bridge. Use `--config /path/to/.env` from another directory. Environment variables override file values.
