import { randomBytes, timingSafeEqual, createHash } from "node:crypto";
import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Bot } from "grammy";
import { RuntimeClient } from "../client/client.js";
import { RuntimeSupervisor } from "../cli/supervisor.js";
import { readSecretLine, setupA1R } from "../cli/setup.js";
import { loadConfig } from "../core/config.js";
import { readSecret, writeSecret } from "../core/credentials.js";
import type { RuntimeEvent } from "../core/types.js";
import { splitTelegramText } from "./text.js";

interface TelegramState {
  botId: string;
  username: string;
  ownerId?: string;
  pairingHash?: string;
  pairingExpiresAt?: string;
}

function statePath(homeDir: string): string {
  return join(homeDir, "telegram.json");
}

function readState(homeDir: string): TelegramState | null {
  try {
    return JSON.parse(readFileSync(statePath(homeDir), "utf8")) as TelegramState;
  } catch {
    return null;
  }
}

function writeState(homeDir: string, state: TelegramState): void {
  mkdirSync(homeDir, { recursive: true, mode: 0o700 });
  chmodSync(homeDir, 0o700);
  const path = statePath(homeDir);
  if (existsSync(path) && lstatSync(path).isSymbolicLink()) throw new Error("Telegram state must not be a symbolic link.");
  const temporary = `${path}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  renameSync(temporary, path);
  chmodSync(path, 0o600);
}

function hash(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

async function setupTelegram(): Promise<string> {
  const config = loadConfig();
  console.log("\nConnect A1R to Telegram\n");
  console.log("In Telegram, open @BotFather, send /newbot, then paste the bot token here.");
  const token = await readSecretLine("Bot token (hidden): ");
  const bot = new Bot(token);
  let me;
  let webhook;
  try {
    me = await bot.api.getMe();
    webhook = await bot.api.getWebhookInfo();
  } catch {
    throw new Error("Telegram could not validate that bot token. Copy a fresh token from @BotFather and try again.");
  }
  if (webhook.url) throw new Error("This bot is connected to a webhook elsewhere. Create a new bot for A1R.");
  await bot.api.setMyCommands([
    { command: "start", description: "Open A1R" },
    { command: "help", description: "What A1R can do" },
    { command: "status", description: "Connection status" },
    { command: "stop", description: "Stop the current response" },
  ]);
  writeSecret("telegram", token, config.homeDir);

  const existing = readState(config.homeDir);
  if (!existing?.ownerId) {
    const code = randomBytes(18).toString("base64url");
    writeState(config.homeDir, {
      botId: String(me.id),
      username: me.username,
      pairingHash: hash(code),
      pairingExpiresAt: new Date(Date.now() + 10 * 60_000).toISOString(),
    });
    console.log(`\nOpen this private pairing link within 10 minutes:\nhttps://t.me/${me.username}?start=pair_${code}`);
  } else {
    writeState(config.homeDir, { ...existing, botId: String(me.id), username: me.username });
    console.log(`@${me.username} is already paired. Starting the gateway…`);
  }
  return token;
}

async function runGateway(token: string): Promise<void> {
  const config = loadConfig();
  const client = new RuntimeClient(config.homeDir);
  const supervisor = new RuntimeSupervisor(client, false, (message) => console.log(`· ${message}`));
  await supervisor.start();
  const bot = new Bot(token);
  const active = new Map<string, string>();
  const isOwner = (chatType: string, userId: number | undefined) => {
    const current = readState(config.homeDir);
    return chatType === "private" && userId !== undefined && current?.ownerId === String(userId);
  };

  bot.command("start", async (ctx) => {
    if (ctx.chat.type !== "private" || !ctx.from) return;
    const current = readState(config.homeDir);
    const payload = ctx.match;
    if (current?.ownerId === String(ctx.from.id)) {
      await ctx.reply("A1R is connected. Message me normally.");
      return;
    }
    if (!current?.pairingHash || !current.pairingExpiresAt || !payload.startsWith("pair_")) {
      await ctx.reply("This A1R bot is not available.");
      return;
    }
    const supplied = hash(payload.slice(5));
    const expected = current.pairingHash;
    const valid = supplied.length === expected.length
      && timingSafeEqual(Buffer.from(supplied), Buffer.from(expected))
      && Date.parse(current.pairingExpiresAt) > Date.now();
    if (!valid) {
      await ctx.reply("That pairing link has expired. Run `a1r telegram setup` locally again.");
      return;
    }
    writeState(config.homeDir, { botId: current.botId, username: current.username, ownerId: String(ctx.from.id) });
    await ctx.reply("Connected. Message me normally—A1R will choose the right context automatically.");
  });

  bot.command("help", async (ctx) => {
    if (!isOwner(ctx.chat.type, ctx.from?.id)) return;
    await ctx.reply("Ask for personal help or coding work in ordinary language. A1R chooses the session, memory, tools, and model for you.");
  });
  bot.command("status", async (ctx) => {
    if (!isOwner(ctx.chat.type, ctx.from?.id)) return;
    await ctx.reply(await client.healthy() ? "A1R is ready." : "A1R is reconnecting.");
  });
  bot.command("stop", async (ctx) => {
    if (!isOwner(ctx.chat.type, ctx.from?.id)) return;
    const requestId = active.get(String(ctx.from?.id));
    if (requestId) await client.cancel(requestId);
    await ctx.reply(requestId ? "Stopped. Your session is saved." : "Nothing is running.");
  });

  bot.on("message:text", async (ctx) => {
    if (ctx.chat.type !== "private" || ctx.message.text.startsWith("/")) return;
    const current = readState(config.homeDir);
    if (current?.ownerId !== String(ctx.from.id)) {
      await ctx.reply("This A1R bot is private.");
      return;
    }
    const senderId = String(ctx.from.id);
    if (active.has(senderId)) {
      await ctx.reply("I’m still working on the previous message. Send /stop first if you want to interrupt it.");
      return;
    }
    const requestId = `telegram:${ctx.update.update_id}`;
    let placeholder: { message_id: number } | null = null;
    let output = "";
    let lastRendered = "Thinking…";
    let renderChain = Promise.resolve();
    const scheduleRender = () => {
      renderChain = renderChain.then(async () => {
        if (!placeholder) return;
        const next = output.trim() || "Thinking…";
        if (next === lastRendered) return;
        lastRendered = next;
        await ctx.api.editMessageText(ctx.chat.id, placeholder.message_id, next.slice(-4096)).catch(() => undefined);
      });
    };
    let timer: NodeJS.Timeout | null = null;
    try {
      placeholder = await ctx.reply("Thinking…", { reply_parameters: { message_id: ctx.message.message_id } });
      active.set(senderId, requestId);
      timer = setInterval(scheduleRender, 900);
      await client.chat({ text: ctx.message.text, channel: "telegram", senderId }, (event: RuntimeEvent) => {
        if (event.type === "text_delta") output += event.delta;
        if (event.type === "tool_start") void ctx.replyWithChatAction("typing");
        if (event.type === "error") output += `${output ? "\n\n" : ""}_${event.message}_`;
      }, requestId);
      if (timer) clearInterval(timer);
      await renderChain;
      const chunks = splitTelegramText(output || "Done.");
      await ctx.api.editMessageText(ctx.chat.id, placeholder.message_id, chunks[0] ?? "Done.").catch(() => undefined);
      for (const chunk of chunks.slice(1)) await ctx.reply(chunk);
    } catch {
      if (timer) clearInterval(timer);
      await renderChain;
      const message = `${output}${output ? "\n\n" : ""}Interrupted. Your session is saved; send another message to continue.`;
      if (placeholder) await ctx.api.editMessageText(ctx.chat.id, placeholder.message_id, message.slice(-4096)).catch(() => undefined);
      else await ctx.reply("I could not start that response. A1R is reconnecting; please try again.").catch(() => undefined);
    } finally {
      if (timer) clearInterval(timer);
      active.delete(senderId);
    }
  });

  bot.catch((error) => console.error(`Telegram gateway error: ${error.message.replaceAll(token, "[redacted]")}`));
  const stop = async () => {
    await bot.stop();
    await supervisor.stop();
  };
  process.once("SIGINT", () => void stop());
  process.once("SIGTERM", () => void stop());
  await bot.start({ onStart: (info) => console.log(`A1R Telegram is online as @${info.username}.`) });
}

export async function runTelegramCommand(args: string[]): Promise<void> {
  const config = loadConfig();
  if (args[0] === "setup") await setupA1R();
  const token = args[0] === "setup" ? await setupTelegram() : readSecret("telegram", config.homeDir);
  if (!token) throw new Error("Telegram is not connected. Run `a1r telegram setup`.");
  try {
    await runGateway(token);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(message.replaceAll(token, "[redacted]"));
  }
}
