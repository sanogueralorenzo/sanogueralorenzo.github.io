import { describe, expect, it } from "vitest";
import { TELEGRAM_SERVICE_LABEL, renderTelegramLaunchAgent } from "./service.js";

describe("Telegram background service", () => {
  it("renders a persistent launch agent with the internal gateway entry point", () => {
    const plist = renderTelegramLaunchAgent({
      executable: "/opt/homebrew/bin/node",
      entryPath: "/opt/a1r & tools/dist/bin/a1r.js",
      workingDirectory: "/opt/a1r & tools",
      homeDir: "/Users/test/.a1r",
      codexCommand: "/opt/homebrew/bin/codex",
      path: "/opt/homebrew/bin:/usr/bin:/bin",
    });

    expect(plist).toContain(`<string>${TELEGRAM_SERVICE_LABEL}</string>`);
    expect(plist).toContain("<string>telegram</string>\n    <string>serve</string>");
    expect(plist).toContain("<key>KeepAlive</key>\n  <true/>");
    expect(plist).toContain("/opt/a1r &amp; tools/dist/bin/a1r.js");
    expect(plist).toContain("/Users/test/.a1r/telegram.log");
    expect(plist).not.toContain("Bot token");
  });

  it("runs TypeScript development entry points through tsx", () => {
    const plist = renderTelegramLaunchAgent({
      executable: "/usr/bin/node",
      entryPath: "/repo/tools/a1r/src/bin/a1r.ts",
      workingDirectory: "/repo/tools/a1r",
      homeDir: "/tmp/a1r",
      codexCommand: "/usr/bin/codex",
    });

    expect(plist).toContain("<string>--import</string>\n    <string>tsx</string>");
  });
});
