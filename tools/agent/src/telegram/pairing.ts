import { randomBytes, timingSafeEqual } from "node:crypto";
import { join } from "node:path";
import { Bot } from "grammy";
import { readSecretLine } from "../cli/setup.js";
import { loadConfig } from "../local/config.js";
import { writeSecret } from "../local/credentials.js";
import { readPrivateJson, writePrivateJson } from "../local/files.js";
import { pairingExpiresAt, pairingHash } from "./text.js";

interface TelegramState {
  username: string;
  ownerId?: string;
  pairingHash?: string;
  pairingExpiresAt?: string;
}

export function readTelegramState(homeDir: string): TelegramState | null {
  return readPrivateJson(join(homeDir, "telegram.json"));
}

function writeState(homeDir: string, state: TelegramState): void {
  writePrivateJson(join(homeDir, "telegram.json"), state);
}

export async function setupTelegram(): Promise<string> {
  const config = loadConfig();
  console.log("\nConnect Agent to Telegram\n");
  console.log("In Telegram, open @BotFather, send /newbot, then paste the bot token here.");
  const token = await readSecretLine("Bot token (hidden): ");
  const bot = new Bot(token);
  let me;
  let webhook;
  try {
    [me, webhook] = await Promise.all([bot.api.getMe(), bot.api.getWebhookInfo()]);
  } catch {
    throw new Error("Telegram could not validate that bot token. Copy a fresh token from @BotFather and try again.");
  }
  if (webhook.url) throw new Error("This bot is connected to a webhook elsewhere. Create a new bot for Agent.");
  await bot.api.setMyCommands([
    { command: "start", description: "Open Agent" },
    { command: "help", description: "What Agent can do" },
    { command: "status", description: "Connection status" },
    { command: "stop", description: "Stop the current response" },
  ]);
  writeSecret("telegram", token, config.homeDir);

  const existing = readTelegramState(config.homeDir);
  if (existing?.ownerId) {
    writeState(config.homeDir, { ...existing, username: me.username });
    console.log(`@${me.username} is already paired.`);
  } else {
    const code = randomBytes(18).toString("base64url");
    writeState(config.homeDir, {
      username: me.username,
      pairingHash: pairingHash(code),
      pairingExpiresAt: pairingExpiresAt(),
    });
    console.log(`\nOpen this private pairing link within 3 minutes:\nhttps://t.me/${me.username}?start=pair_${code}`);
  }
  return token;
}

export function pairTelegramOwner(homeDir: string, userId: number, payload: string): "connected" | "owner" | "unavailable" | "expired" {
  const state = readTelegramState(homeDir);
  if (state?.ownerId === String(userId)) return "owner";
  if (!state?.pairingHash || !state.pairingExpiresAt || !payload.startsWith("pair_")) return "unavailable";
  const supplied = pairingHash(payload.slice(5));
  if (!timingSafeEqual(Buffer.from(supplied), Buffer.from(state.pairingHash)) || Date.parse(state.pairingExpiresAt) <= Date.now()) return "expired";
  writeState(homeDir, { username: state.username, ownerId: String(userId) });
  return "connected";
}
