# Headless setup

On a headless Linux host with Node 26+, install Agent and at least one official CLI. Sign in under the same OS account that runs Agent:

- Codex: `codex login --device-auth`
- Claude Code: `claude auth login`
- Google Antigravity: `agy acp --login`

```bash
cd agent
npm ci --ignore-scripts
npm start
```

To use the UI from your laptop, forward its port and open `http://127.0.0.1:4181`:

```bash
ssh -N -L 4181:127.0.0.1:4180 user@pi-host
```

The service installer and native Computer Use require macOS. Coding and shell tools run on the Agent host.
