import { Bot, InputFile, type Context } from "grammy";
import { RuntimeClient } from "../client/client.js";
import { RuntimeSupervisor } from "../cli/supervisor.js";
import { loadConfig } from "../local/config.js";
import { readSecret } from "../local/credentials.js";
import { pairTelegramOwner, readTelegramState } from "./pairing.js";
import { keepTelegramTyping } from "./text.js";
import { checkTelegramVoiceSize, isTelegramOwner, telegramFailure, type TelegramTurnResult, TelegramTurns } from "./turn.js";

async function runGateway(token: string): Promise<void> {
  const config = loadConfig();
  const client = new RuntimeClient(config.homeDir);
  const supervisor = new RuntimeSupervisor(client, false, (message) => console.log(`· ${message}`));
  await supervisor.start();
  const bot = new Bot(token);
  let stopping: Promise<void> | null = null;
  const deliveryController = new AbortController();
  let deliveryTask: Promise<void> | null = null;
  let markDeliveryReady!: () => void;
  const deliveryReady = new Promise<void>((resolve) => { markDeliveryReady = resolve; });
  const ownerId = () => readTelegramState(config.homeDir)?.ownerId;
  const isOwner = (ctx: Context) => isTelegramOwner(ownerId(), ctx.chat?.type, ctx.from?.id);
  const turns = new TelegramTurns(client);
  const stop = (): Promise<void> => stopping ??= (async () => {
    deliveryController.abort();
    markDeliveryReady();
    supervisor.stop();
    await Promise.all([bot.stop(), deliveryTask]);
  })();

  const deliver = async (result: TelegramTurnResult): Promise<void> => {
    const owner = ownerId();
    if (!owner) return;
    for (const chunk of result.chunks) await bot.api.sendMessage(owner, chunk);
    for (const artifact of result.artifacts) {
      if (artifact.kind === "image") await bot.api.sendPhoto(owner, new InputFile(artifact.path));
      else await bot.api.sendDocument(owner, new InputFile(artifact.path, artifact.name));
    }
    if (!result.chunks.length && !result.artifacts.length) await bot.api.sendMessage(owner, "Done.");
  };

  const observe = async (): Promise<void> => {
    let stopTyping: () => void = () => undefined;
    while (!deliveryController.signal.aborted) {
      try {
        const events = await client.events(deliveryController.signal);
        markDeliveryReady();
        for await (const envelope of events) {
          if (envelope.event.type === "turn") {
            const owner = ownerId();
            stopTyping = owner ? keepTelegramTyping(() => bot.api.sendChatAction(owner, "typing")) : () => undefined;
          }
          const result = turns.consume(envelope);
          if (result) {
            stopTyping();
            stopTyping = () => undefined;
            await deliver(result).catch((error) => console.error(`Telegram delivery error: ${String(error).replaceAll(token, "[redacted]")}`));
          }
        }
      } catch {
        if (deliveryController.signal.aborted) return;
        stopTyping();
        stopTyping = () => undefined;
        const interrupted = turns.interrupt();
        if (interrupted) await deliver(interrupted).catch(() => undefined);
        await client.waitUntilHealthy().catch(() => undefined);
      }
    }
  };

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
    if (isOwner(ctx)) await ctx.reply("Message Agent normally. Use /new for a new conversation or /stop to interrupt a response.");
  });
  bot.command("new", async (ctx) => {
    if (!isOwner(ctx)) return;
    turns.newConversation();
    await ctx.reply("New conversation ready.");
  });
  bot.command("status", async (ctx) => {
    if (!isOwner(ctx)) return;
    if (!await client.healthy()) return void await ctx.reply("Agent is reconnecting.");
    await ctx.reply("Agent is ready.");
  });
  bot.command("stop", async (ctx) => {
    if (!isOwner(ctx)) return;
    if (!await turns.stop()) await ctx.reply("Nothing is running.");
  });

  const respond = async (ctx: Context, prepare: () => Promise<{ text: string; attachmentIds?: string[] }>): Promise<void> => {
    if (!ctx.chat || !ctx.from || !ctx.message || ctx.chat.type !== "private") return;
    if (!isOwner(ctx)) return void await ctx.reply("This Agent bot is private.");
    try {
      if (!await turns.submit(prepare)) {
        await ctx.reply("I’m still working on the previous message. Send /stop first if you want to interrupt it.");
      }
    } catch (error) {
      await ctx.reply(telegramFailure(error));
    }
  };

  bot.on("message:text", async (ctx) => {
    if (ctx.chat.type === "private" && !ctx.message.text.startsWith("/")) await respond(ctx, async () => ({ text: ctx.message.text }));
  });
  bot.on("message:voice", async (ctx) => respond(ctx, async () => {
    const voice = ctx.message.voice;
    checkTelegramVoiceSize(voice.file_size);
    const file = await bot.api.getFile(voice.file_id);
    if (!file.file_path) throw new Error("Telegram did not provide the voice note.");
    const response = await fetch(`https://api.telegram.org/file/bot${token}/${file.file_path}`);
    if (!response.ok) throw new Error("Telegram could not download the voice note.");
    const data = new Uint8Array(await response.arrayBuffer());
    checkTelegramVoiceSize(data.byteLength);
    const attachment = await client.uploadAttachment({
      name: `voice-${voice.file_unique_id}.ogg`, mimeType: voice.mime_type ?? "audio/ogg", data,
    });
    return { text: "", attachmentIds: [attachment.id] };
  }));

  bot.catch((error) => console.error(`Telegram gateway error: ${error.message.replaceAll(token, "[redacted]")}`));
  process.once("SIGINT", () => void stop());
  process.once("SIGTERM", () => void stop());
  deliveryTask = observe();
  await deliveryReady;
  if (deliveryController.signal.aborted) return;
  await bot.start({ onStart: async (info) => {
    await bot.api.setMyCommands([
      { command: "new", description: "Start a new conversation" },
      { command: "help", description: "What Agent can do" },
      { command: "status", description: "Connection status" },
      { command: "stop", description: "Stop the current response" },
    ]);
    console.log(`Agent Telegram is online as @${info.username}.`);
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
