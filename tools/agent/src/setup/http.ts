import type { IncomingMessage } from "node:http";
import type { AgentSetupService } from "./service.js";
import { readJson } from "../server/request.js";

export type RuntimeSetup = Pick<AgentSetupService,
  "status" | "connectApiKey" | "logout" | "startCodexLogin" | "waitForCodexLogin">;

export async function handleSetupRequest(
  route: string,
  request: IncomingMessage,
  setup: RuntimeSetup,
): Promise<{ status: number; body: unknown } | null> {
  const login = /^POST \/v1\/setup\/codex\/login\/([^/]*)\/wait$/.exec(route);
  if (login) {
    const loginId = decodeURIComponent(login[1]!);
    if (!loginId) throw new Error("login id is required");
    return { status: 200, body: await setup.waitForCodexLogin(loginId) };
  }

  switch (route) {
    case "GET /v1/setup": return { status: 200, body: await setup.status() };
    case "POST /v1/setup/logout": {
      await setup.logout();
      return { status: 200, body: { connected: false } };
    }
    case "POST /v1/setup/openai": {
      const { apiKey } = await readJson(request);
      const key = typeof apiKey === "string" ? apiKey.trim() : "";
      if (!key.startsWith("sk-")) throw new Error("That does not look like an OpenAI API key.");
      await setup.connectApiKey(key);
      return { status: 200, body: { connected: true } };
    }
    case "POST /v1/setup/codex/login": {
      const { mode } = await readJson(request);
      if (mode !== "browser" && mode !== "headless") throw new Error("login mode must be browser or headless");
      return { status: 200, body: await setup.startCodexLogin(mode) };
    }
    default: return null;
  }
}
