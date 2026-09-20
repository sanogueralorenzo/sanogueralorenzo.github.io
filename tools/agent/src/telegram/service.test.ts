import { describe, expect, it } from "vitest";
import { TELEGRAM_SERVICE_LABEL, renderTelegramGatewayLauncher, renderTelegramLaunchAgent } from "./service.js";

describe("Telegram background service", () => {
  it("attributes the persistent launch agent to Agent", () => {
    const plist = renderTelegramLaunchAgent({
      launcherPath: "/Users/test/.agent/bin/Agent",
      workingDirectory: "/opt/agent & tools",
      homeDir: "/Users/test/.agent",
      codexCommand: "/opt/homebrew/bin/codex",
      path: "/opt/homebrew/bin:/usr/bin:/bin",
    });

    expect(plist).toContain(`<string>${TELEGRAM_SERVICE_LABEL}</string>`);
    expect(plist).toContain("<key>KeepAlive</key><true/>");
    expect(plist).toContain("<key>Program</key><string>/Users/test/.agent/bin/Agent</string>");
    expect(plist).toContain("<key>AGENT_HOME</key>\n    <string>/Users/test/.agent</string>");
    expect(plist).toContain("<key>AGENT_CODEX_COMMAND</key>\n    <string>/opt/homebrew/bin/codex</string>");
    expect(plist).toContain("/Users/test/.agent/telegram.log");
    expect(plist).not.toContain("Bot token");
  });

  it("renders a launcher for production and TypeScript development entry points", () => {
    expect(renderTelegramGatewayLauncher("/opt/homebrew/bin/node", "/repo/tools/agent/dist/telegram/main.js"))
      .toBe("#!/bin/sh\nexec '/opt/homebrew/bin/node' '/repo/tools/agent/dist/telegram/main.js'\n");

    expect(renderTelegramGatewayLauncher("/usr/bin/node", "/repo/tools/agent/src/telegram/main.ts"))
      .toContain("exec '/usr/bin/node' '--import' 'tsx' '/repo/tools/agent/src/telegram/main.ts'");
  });
});
