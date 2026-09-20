import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { writePrivateJson } from "../local/files.js";
import { temporary } from "../test-support.js";
import { pairTelegramOwner, readTelegramState } from "./pairing.js";
import { pairingHash } from "./text.js";

function pairing(code: string, expiresAt: string) {
  const homeDir = temporary("agent-telegram-pairing-");
  writePrivateJson(join(homeDir, "telegram.json"), {
    username: "agent_test_bot",
    pairingHash: pairingHash(code),
    pairingExpiresAt: expiresAt,
  });
  return homeDir;
}

describe("Telegram pairing", () => {
  it("connects a valid link once and keeps the owner", () => {
    const homeDir = pairing("private-code", "2999-01-01T00:00:00.000Z");

    expect(pairTelegramOwner(homeDir, 42, "pair_private-code")).toBe("connected");
    expect(pairTelegramOwner(homeDir, 42, "pair_private-code")).toBe("owner");
    expect(pairTelegramOwner(homeDir, 7, "pair_private-code")).toBe("unavailable");
    expect(readTelegramState(homeDir)).toEqual({ username: "agent_test_bot", ownerId: "42" });
  });

  it("rejects an expired link without assigning an owner", () => {
    const homeDir = pairing("expired-code", "2000-01-01T00:00:00.000Z");

    expect(pairTelegramOwner(homeDir, 42, "pair_expired-code")).toBe("expired");
    expect(readTelegramState(homeDir)?.ownerId).toBeUndefined();
  });
});
