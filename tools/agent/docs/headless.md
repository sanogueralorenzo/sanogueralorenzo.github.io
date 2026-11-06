# Headless setup

On a headless Linux host with Node 26+, install dependencies and log in from the terminal before starting Agent:

```bash
cd tools/agent
npm ci --ignore-scripts
npm run login -- openai
npm start
```

`npm run login` lists provider IDs and methods. Login prefers OAuth when available; append `api_key` for key setup, for example `npm run login -- openai api_key`. The CLI uses Pi's authentication and the same credentials, installation ID, and selected provider as the UI. Restart Agent if it was already running when CLI login finished.

Open the CLI's sign-in link in your laptop's browser. Pi's device-code, copy-code, and manual redirect prompts remain available in the terminal where supported. OpenAI browser login needs port 1455 forwarded over SSH, or the final redirect URL pasted into the CLI.

To use the UI from your laptop, forward the web UI and OpenAI's callback port:

```bash
ssh -N -L 4181:127.0.0.1:4180 -L 1455:127.0.0.1:1455 user@pi-host
```

Open `http://127.0.0.1:4181` on your laptop and sign in there. Port 1455 must be free on your laptop; forwarding it lets OpenAI return to Agent on the host automatically. API keys need no browser callback.

The service installer is macOS-only. Codex Computer Use requires the desktop plugin; it is unavailable on a headless Raspberry Pi. Coding and shell tools run on the host.
