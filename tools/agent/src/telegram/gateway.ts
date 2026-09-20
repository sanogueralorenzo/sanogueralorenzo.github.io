import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Bot, InputFile, type Context } from "grammy";
import { RuntimeClient } from "../client/client.js";
import { RuntimeSupervisor } from "../cli/supervisor.js";
import type { RuntimeEvent } from "../conversation/types.js";
import { loadConfig } from "../local/config.js";
import { readSecret } from "../local/credentials.js";
import { MAX_ATTACHMENT_BYTES } from "../workspace/assets.js";
import { pairTelegramOwner, readTelegramState } from "./pairing.js";
import { acknowledgeUpdate, pendingUpdateOwner, TelegramSelfUpdate } from "./self-update.js";
import { keepTelegramTyping, splitTelegramText } from "./text.js";

async function runGateway(token: string): Promise<void> {
  const config = loadConfig();
  const client = new RuntimeClient(config.homeDir);
  const supervisor = new RuntimeSupervisor(client, false, (message) => console.log(`· ${message}`));
  await supervisor.start();
  const bot = new Bot(token);
  let activeRequestId: string | null = null;
  let stopping: Promise<void> | null = null;
  const ownerId = () => readTelegramState(config.homeDir)?.ownerId;
  const isOwner = (ctx: Context) => ctx.chat?.type === "private" && ctx.from && ownerId() === String(ctx.from.id);
  const updater = new TelegramSelfUpdate({
    projectRoot: join(dirname(fileURLToPath(import.meta.url)), "../.."),
    homeDir: config.homeDir,
    requestRuntimeRestart: () => client.requestRestart(),
    stopGateway: async () => stop(),
    ownerId,
    onFailure: async () => {
      const owner = ownerId();
      if (owner) await bot.api.sendMessage(owner, "Agent update failed verification. The current version is still running.").catch(() => undefined);
    },
  });
  const stop = (): Promise<void> => stopping ??= (async () => {
    updater.stop();
    await Promise.all([bot.stop(), supervisor.stop()]);
  })();

  bot.command("start", async (ctx) => {
    if (ctx.chat.type !== "private" || !ctx.from) return;
    const result = pairTelegramOwner(config.homeDir, ctx.from.id, ctx.match);
    const replies = {
      owner: "Agent is connected. Message me normally.",
      unavailable: "This Agent bot is not available.",
      expired: "That pairing link has expired. Run `agent telegram setup` locally again.",
      connected: "Connected. Message me normally—Agent will choose the right context automatically.",
    };
    await ctx.reply(replies[result]);
  });
  bot.command("help", async (ctx) => {
    if (isOwner(ctx)) await ctx.reply("Ask for personal help or coding work in ordinary language. Agent chooses the session, memory, tools, and model for you.");
  });
  bot.command("status", async (ctx) => {
    if (isOwner(ctx)) await ctx.reply(await client.healthy() ? "Agent is ready." : "Agent is reconnecting.");
  });
  bot.command("stop", async (ctx) => {
    if (!isOwner(ctx)) return;
    if (activeRequestId) await client.cancel(activeRequestId);
    else await ctx.reply("Nothing is running.");
  });

  const respond = async (ctx: Context, prepare: () => Promise<{ text: string; attachmentIds?: string[] }>): Promise<void> => {
    if (!ctx.chat || !ctx.from || !ctx.message || ctx.chat.type !== "private") return;
    if (!isOwner(ctx)) return void await ctx.reply("This Agent bot is private.");
    if (activeRequestId) return void await ctx.reply("I’m still working on the previous message. Send /stop first if you want to interrupt it.");
    if (!updater.beginTurn()) return void await ctx.reply("Applying an Agent update. I’ll reconnect shortly.");
    const requestId = `telegram:${ctx.update.update_id}`;
    let output = "";
    let runtimeError = "";
    const artifacts: Array<Extract<RuntimeEvent, { type: "artifact" }>["artifact"]> = [];
    const stopTyping = keepTelegramTyping(() => ctx.replyWithChatAction("typing"));
    try {
      activeRequestId = requestId;
      await client.chat({ ...await prepare(), channel: "telegram" }, (event) => {
        if (event.type === "text_delta") output += event.delta;
        if (event.type === "artifact") artifacts.push(event.artifact);
        if (event.type === "error") runtimeError = event.message;
      }, requestId);
      stopTyping();
      const chunks = splitTelegramText([output.trim(), runtimeError].filter(Boolean).join("\n\n"));
      if (chunks[0]) {
        await ctx.reply(chunks[0], { reply_parameters: { message_id: ctx.message.message_id } });
        for (const chunk of chunks.slice(1)) await ctx.reply(chunk);
      }
      for (const artifact of artifacts) {
        const options = chunks.length ? {} : { reply_parameters: { message_id: ctx.message.message_id } };
        if (artifact.kind === "image") await ctx.replyWithPhoto(new InputFile(artifact.path), options);
        else await ctx.replyWithDocument(new InputFile(artifact.path, artifact.name), options);
      }
      if (!chunks.length && !artifacts.length) await ctx.reply("Done.", { reply_parameters: { message_id: ctx.message.message_id } });
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
      activeRequestId = null;
      updater.endTurn();
    }
  };

  bot.on("message:text", async (ctx) => {
    if (ctx.chat.type === "private" && !ctx.message.text.startsWith("/")) await respond(ctx, async () => ({ text: ctx.message.text }));
  });
  bot.on("message:voice", async (ctx) => respond(ctx, async () => {
    const voice = ctx.message.voice;
    if (voice.file_size && voice.file_size > MAX_ATTACHMENT_BYTES) throw new Error("Voice note exceeds the 25 MB limit.");
    const file = await bot.api.getFile(voice.file_id);
    if (!file.file_path) throw new Error("Telegram did not provide the voice note.");
    const response = await fetch(`https://api.telegram.org/file/bot${token}/${file.file_path}`);
    if (!response.ok) throw new Error("Telegram could not download the voice note.");
    const data = new Uint8Array(await response.arrayBuffer());
    if (data.byteLength > MAX_ATTACHMENT_BYTES) throw new Error("Voice note exceeds the 25 MB limit.");
    const attachment = await client.uploadAttachment({
      name: `voice-${voice.file_unique_id}.ogg`, mimeType: voice.mime_type ?? "audio/ogg", data,
    });
    return { text: "", attachmentIds: [attachment.id] };
  }));

  bot.catch((error) => console.error(`Telegram gateway error: ${error.message.replaceAll(token, "[redacted]")}`));
  process.once("SIGINT", () => void stop());
  process.once("SIGTERM", () => void stop());
  await bot.start({ onStart: async (info) => {
    console.log(`Agent Telegram is online as @${info.username}.`);
    await updater.start();
    const owner = pendingUpdateOwner(config.homeDir);
    if (owner && await bot.api.sendMessage(owner, "Agent updated and reconnected.").then(() => true, () => false)) {
      acknowledgeUpdate(config.homeDir);
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
    throw new Error((error instanceof Error ? error.message : String(error)).replaceAll(token, "[redacted]"));
  }
}
