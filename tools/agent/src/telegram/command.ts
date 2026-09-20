import { randomBytes, timingSafeEqual } from "node:crypto";
import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Bot, InputFile, type Context } from "grammy";
import { RuntimeClient } from "../client/client.js";
import { RuntimeSupervisor } from "../cli/supervisor.js";
import { isAgentConfigured, readSecretLine, setupAgent } from "../cli/setup.js";
import { loadConfig } from "../core/config.js";
import { readSecret, writeSecret } from "../core/credentials.js";
import type { RuntimeEvent } from "../core/types.js";
import { MAX_ATTACHMENT_BYTES } from "../core/assets.js";
import { installTelegramBackgroundService } from "./service.js";
import { acknowledgeUpdate, pendingUpdateOwner, TelegramSelfUpdate } from "./self-update.js";
import { keepTelegramTyping, pairingExpiresAt, pairingHash, splitTelegramText } from "./text.js";

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

async function setupTelegram(): Promise<string> {
  const config = loadConfig();
  console.log("\nConnect Agent to Telegram\n");
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
  if (webhook.url) throw new Error("This bot is connected to a webhook elsewhere. Create a new bot for Agent.");
  await bot.api.setMyCommands([
    { command: "start", description: "Open Agent" },
    { command: "help", description: "What Agent can do" },
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
      pairingHash: pairingHash(code),
      pairingExpiresAt: pairingExpiresAt(),
    });
    console.log(`\nOpen this private pairing link within 3 minutes:\nhttps://t.me/${me.username}?start=pair_${code}`);
  } else {
    writeState(config.homeDir, { ...existing, botId: String(me.id), username: me.username });
    console.log(`@${me.username} is already paired.`);
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
  let stopping: Promise<void> | null = null;
  const isOwner = (chatType: string, userId: number | undefined) => {
    const current = readState(config.homeDir);
    return chatType === "private" && userId !== undefined && current?.ownerId === String(userId);
  };
  const updater = new TelegramSelfUpdate({
    projectRoot: join(dirname(fileURLToPath(import.meta.url)), "../.."),
    homeDir: config.homeDir,
    requestRuntimeRestart: () => client.requestRestart(),
    stopGateway: async () => stop(),
    ownerId: () => readState(config.homeDir)?.ownerId,
    onStatus: (message) => console.log(`· ${message}`),
    onFailure: async () => {
      const ownerId = readState(config.homeDir)?.ownerId;
      if (ownerId) await bot.api.sendMessage(ownerId, "Agent update failed verification. The current version is still running.").catch(() => undefined);
    },
  });

  const stop = (): Promise<void> => {
    if (stopping) return stopping;
    stopping = (async () => {
      updater.stop();
      await Promise.all([bot.stop(), supervisor.stop()]);
    })();
    return stopping;
  };

  bot.command("start", async (ctx) => {
    if (ctx.chat.type !== "private" || !ctx.from) return;
    const current = readState(config.homeDir);
    const payload = ctx.match;
    if (current?.ownerId === String(ctx.from.id)) {
      await ctx.reply("Agent is connected. Message me normally.");
      return;
    }
    if (!current?.pairingHash || !current.pairingExpiresAt || !payload.startsWith("pair_")) {
      await ctx.reply("This Agent bot is not available.");
      return;
    }
    const supplied = pairingHash(payload.slice(5));
    const expected = current.pairingHash;
    const valid = supplied.length === expected.length
      && timingSafeEqual(Buffer.from(supplied), Buffer.from(expected))
      && Date.parse(current.pairingExpiresAt) > Date.now();
    if (!valid) {
      await ctx.reply("That pairing link has expired. Run `agent telegram setup` locally again.");
      return;
    }
    writeState(config.homeDir, { botId: current.botId, username: current.username, ownerId: String(ctx.from.id) });
    await ctx.reply("Connected. Message me normally—Agent will choose the right context automatically.");
  });

  bot.command("help", async (ctx) => {
    if (!isOwner(ctx.chat.type, ctx.from?.id)) return;
    await ctx.reply("Ask for personal help or coding work in ordinary language. Agent chooses the session, memory, tools, and model for you.");
  });
  bot.command("status", async (ctx) => {
    if (!isOwner(ctx.chat.type, ctx.from?.id)) return;
    await ctx.reply(await client.healthy() ? "Agent is ready." : "Agent is reconnecting.");
  });
  bot.command("stop", async (ctx) => {
    if (!isOwner(ctx.chat.type, ctx.from?.id)) return;
    const requestId = active.get(String(ctx.from?.id));
    if (requestId) await client.cancel(requestId);
    if (!requestId) await ctx.reply("Nothing is running.");
  });

  const respond = async (
    ctx: Context,
    prepare: () => Promise<{ text: string; attachmentIds?: string[] }>,
  ): Promise<void> => {
    if (!ctx.chat || !ctx.from || !ctx.message || ctx.chat.type !== "private") return;
    const current = readState(config.homeDir);
    if (current?.ownerId !== String(ctx.from.id)) {
      await ctx.reply("This Agent bot is private.");
      return;
    }
    const senderId = String(ctx.from.id);
    if (active.has(senderId)) {
      await ctx.reply("I’m still working on the previous message. Send /stop first if you want to interrupt it.");
      return;
    }
    if (!updater.beginTurn()) {
      await ctx.reply("Applying an Agent update. I’ll reconnect shortly.");
      return;
    }
    const requestId = `telegram:${ctx.update.update_id}`;
    let output = "";
    let runtimeError = "";
    const artifacts: Array<Extract<RuntimeEvent, { type: "artifact" }>["artifact"]> = [];
    const stopTyping = keepTelegramTyping(() => ctx.replyWithChatAction("typing"));
    try {
      active.set(senderId, requestId);
      const input = await prepare();
      await client.chat({ ...input, channel: "telegram", senderId }, (event: RuntimeEvent) => {
        if (event.type === "text_delta") output += event.delta;
        if (event.type === "artifact") artifacts.push(event.artifact);
        if (event.type === "error") runtimeError = event.message;
      }, requestId);
      stopTyping();
      const finalText = [output.trim(), runtimeError].filter(Boolean).join("\n\n");
      const chunks = finalText ? splitTelegramText(finalText) : [];
      if (chunks[0]) {
        await ctx.reply(chunks[0], { reply_parameters: { message_id: ctx.message.message_id } });
        for (const chunk of chunks.slice(1)) await ctx.reply(chunk);
      }
      for (const artifact of artifacts) {
        const options = chunks.length === 0
          ? { reply_parameters: { message_id: ctx.message.message_id } }
          : {};
        if (artifact.kind === "image") await ctx.replyWithPhoto(new InputFile(artifact.path), options);
        else await ctx.replyWithDocument(new InputFile(artifact.path, artifact.name), options);
      }
      if (chunks.length === 0 && artifacts.length === 0) {
        await ctx.reply("Done.", { reply_parameters: { message_id: ctx.message.message_id } });
      }
    } catch (error) {
      stopTyping();
      const message = output.trim()
        ? `${output.trim()}\n\nInterrupted. Your session is saved; send another message to continue.`
        : error instanceof Error && /25 MB/.test(error.message)
          ? error.message
          : "I could not finish that response. Your session is saved; please try again.";
      await ctx.reply(message, { reply_parameters: { message_id: ctx.message.message_id } }).catch(() => undefined);
    } finally {
      stopTyping();
      active.delete(senderId);
      updater.endTurn();
    }
  };

  bot.on("message:text", async (ctx) => {
    if (ctx.chat.type !== "private" || ctx.message.text.startsWith("/")) return;
    await respond(ctx, async () => ({ text: ctx.message.text }));
  });

  bot.on("message:voice", async (ctx) => {
    await respond(ctx, async () => {
      const voice = ctx.message.voice;
      if (voice.file_size && voice.file_size > MAX_ATTACHMENT_BYTES) throw new Error("Voice note exceeds the 25 MB limit.");
      const file = await bot.api.getFile(voice.file_id);
      if (!file.file_path) throw new Error("Telegram did not provide the voice note.");
      const response = await fetch(`https://api.telegram.org/file/bot${token}/${file.file_path}`);
      if (!response.ok) throw new Error("Telegram could not download the voice note.");
      const data = new Uint8Array(await response.arrayBuffer());
      if (data.byteLength > MAX_ATTACHMENT_BYTES) throw new Error("Voice note exceeds the 25 MB limit.");
      const attachment = await client.uploadAttachment({
        name: `voice-${voice.file_unique_id}.ogg`,
        mimeType: voice.mime_type ?? "audio/ogg",
        data,
      });
      return { text: "", attachmentIds: [attachment.id] };
    });
  });

  bot.catch((error) => console.error(`Telegram gateway error: ${error.message.replaceAll(token, "[redacted]")}`));
  process.once("SIGINT", () => void stop());
  process.once("SIGTERM", () => void stop());
  await bot.start({ onStart: async (info) => {
    console.log(`Agent Telegram is online as @${info.username}.`);
    await updater.start();
    const ownerId = pendingUpdateOwner(config.homeDir);
    if (ownerId) {
      const delivered = await bot.api.sendMessage(ownerId, "Agent updated and reconnected.")
        .then(() => true, () => false);
      if (delivered) acknowledgeUpdate(config.homeDir);
    }
  } });
}

export async function runConfiguredTelegramGateway(): Promise<void> {
  const config = loadConfig();
  const token = readSecret("telegram", config.homeDir);
  if (!token) throw new Error("Telegram is not connected. Run `agent telegram setup`.");
  try {
    await runGateway(token);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(message.replaceAll(token, "[redacted]"));
  }
}

export async function runTelegramCommand(args: string[]): Promise<void> {
  const config = loadConfig();
  if (args[0] !== undefined && args[0] !== "setup") {
    throw new Error(`Unknown Telegram command: ${args[0]}`);
  }
  if (args[0] === "setup") {
    const setupArgs = args.slice(1);
    if (setupArgs.length > 0 || !await isAgentConfigured()) await setupAgent(setupArgs);
  }
  const token = args[0] === "setup" ? await setupTelegram() : readSecret("telegram", config.homeDir);
  if (!token) throw new Error("Telegram is not connected. Run `agent telegram setup`.");
  try {
    await installTelegramBackgroundService(config);
    console.log("Agent Telegram is running in the background.");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(message.replaceAll(token, "[redacted]"));
  }
}
