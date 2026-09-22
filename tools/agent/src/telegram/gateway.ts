import { Bot, InputFile, type Context } from "grammy";
import { RuntimeClient, RuntimeProtocolError } from "../client/client.js";
import { RuntimeSupervisor } from "../client/supervisor.js";
import { loadConfig } from "../local/config.js";
import { readTelegramToken } from "./credentials.js";
import { pairTelegramOwner, readTelegramState } from "./pairing.js";
import { keepTelegramTyping, splitTelegramText } from "./text.js";
import { checkTelegramVoiceSize, isTelegramOwner, telegramFailure, type TelegramTurnResult, TelegramTurns } from "./turn.js";

async function runGateway(token: string): Promise<void> {
  const config = loadConfig();
  const client = new RuntimeClient(config.homeDir);
  const supervisor = new RuntimeSupervisor(client, false, (message) => console.log(`· ${message}`));
  await supervisor.start();
  const bot = new Bot(token);
  let stopping: Promise<void> | null = null;
  const deliveryController = new AbortController();
  let streamController: AbortController | null = null;
  let subscribedSessionId: string | undefined;
  let deliveryTask: Promise<void> | null = null;
  let deliveryStarted = false;
  let markDeliveryReady!: () => void;
  let failDeliveryReady!: (error: Error) => void;
  const deliveryReady = new Promise<void>((resolve, reject) => { markDeliveryReady = resolve; failDeliveryReady = reject; });
  const ownerId = () => readTelegramState(config.homeDir)?.ownerId;
  const isOwner = (ctx: Context) => isTelegramOwner(ownerId(), ctx.chat?.type, ctx.from?.id);
  const turns = new TelegramTurns(client, ownerId);
  const switchDelivery = () => {
    if (subscribedSessionId && turns.selectedSessionId !== subscribedSessionId) streamController?.abort();
  };
  let stopTyping: () => void = () => undefined;
  let typing = false;
  const syncTyping = () => {
    const owner = ownerId();
    if (owner && turns.hasActiveRun()) {
      if (!typing) {
        stopTyping = keepTelegramTyping(() => bot.api.sendChatAction(owner, "typing"));
        typing = true;
      }
    } else if (typing) {
      stopTyping();
      typing = false;
    }
  };
  const stop = (): Promise<void> => stopping ??= (async () => {
    stopTyping();
    deliveryController.abort();
    streamController?.abort();
    markDeliveryReady();
    supervisor.stop();
    await Promise.all([bot.stop(), deliveryTask]);
  })();

  const deliver = async (result: TelegramTurnResult): Promise<void> => {
    const owner = ownerId();
    if (!owner) return;
    for (const [index, chunk] of result.chunks.entries()) await bot.api.sendMessage(owner, chunk,
      result.taskSessionId && index === result.chunks.length - 1
        ? { reply_markup: { inline_keyboard: [[{ text: "View task", callback_data: `task:${result.taskSessionId}` }]] } }
        : {});
    for (const artifact of result.artifacts) {
      if (artifact.kind === "image") await bot.api.sendPhoto(owner, new InputFile(artifact.path));
      else await bot.api.sendDocument(owner, new InputFile(artifact.path, artifact.name));
    }
    if (!result.chunks.length && !result.artifacts.length) await bot.api.sendMessage(owner, "Done.");
  };

  const observe = async (): Promise<void> => {
    while (!deliveryController.signal.aborted) {
      let abortStream: (() => void) | undefined;
      try {
        if (!ownerId()) {
          markDeliveryReady();
          await new Promise((resolve) => setTimeout(resolve, 500));
          continue;
        }
        subscribedSessionId = await turns.ensureSession();
        streamController = new AbortController();
        const stream = streamController;
        abortStream = () => stream.abort();
        deliveryController.signal.addEventListener("abort", abortStream, { once: true });
        const events = await client.events(streamController.signal, subscribedSessionId);
        for await (const envelope of events) {
          if (envelope.event.type === "snapshot") {
            deliveryStarted = true;
            markDeliveryReady();
            stopTyping();
            typing = false;
            const recovered = await turns.reconcile(envelope.event.snapshot);
            syncTyping();
            for (const result of recovered) await deliver(result).catch((error) => console.error(`Telegram delivery error: ${String(error).replaceAll(token, "[redacted]")}`));
            continue;
          }
          const result = turns.consume(envelope);
          syncTyping();
          if (result) {
            await deliver(result).catch((error) => console.error(`Telegram delivery error: ${String(error).replaceAll(token, "[redacted]")}`));
            switchDelivery();
          }
        }
      } catch (error) {
        if (deliveryController.signal.aborted) { stopTyping(); return; }
        if (streamController?.signal.aborted) continue;
        if (error instanceof RuntimeProtocolError) {
          stopTyping();
          deliveryController.abort();
          supervisor.stop();
          if (deliveryStarted) {
            console.error(error.message);
            void bot.stop().catch(() => undefined);
          } else failDeliveryReady(error);
          return;
        }
        stopTyping();
        typing = false;
        await client.waitUntilHealthy().catch(() => undefined);
      } finally {
        if (abortStream) deliveryController.signal.removeEventListener("abort", abortStream);
        streamController = null;
        subscribedSessionId = undefined;
      }
    }
    stopTyping();
  };

  bot.command("start", async (ctx) => {
    if (ctx.chat.type !== "private" || !ctx.from) return;
    const result = pairTelegramOwner(config.homeDir, ctx.from.id, ctx.match);
    if (result === "connected" || result === "owner") await turns.ensureSession();
    const replies = {
      owner: "Agent is connected. Message me normally.",
      unavailable: "This Agent bot is not available.",
      expired: "That pairing link has expired. Run `agent telegram setup` locally again.",
      connected: "Connected. Message me normally—Agent will choose the right context automatically.",
    };
    await ctx.reply(replies[result]);
  });
  bot.command("help", async (ctx) => {
    if (isOwner(ctx)) await ctx.reply("Message Agent normally. Use /home for your tasks, /new for a direct conversation, or /stop to interrupt.");
  });
  bot.command("home", async (ctx) => {
    if (!isOwner(ctx)) return;
    await turns.home();
    switchDelivery();
    await ctx.reply("Home ready.");
  });
  bot.command("new", async (ctx) => {
    if (!isOwner(ctx)) return;
    await turns.newConversation();
    switchDelivery();
    syncTyping();
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
  bot.callbackQuery(/^task:([a-f0-9-]+)$/, async (ctx) => {
    if (!isOwner(ctx)) return void await ctx.answerCallbackQuery();
    await turns.openTask(ctx.match[1]!);
    switchDelivery();
    const transcript = await client.transcript(ctx.match[1]!);
    const answer = transcript.messages.filter((message) => message.role === "assistant").at(-1)?.content ?? "No response yet.";
    await ctx.answerCallbackQuery();
    await ctx.reply(`Opened “${transcript.session.title}”. Continue here; /home returns to your tasks.`);
    for (const chunk of splitTelegramText(answer)) await ctx.reply(chunk);
  });

  const respond = async (ctx: Context, prepare: () => Promise<{ text: string; attachmentIds?: string[] }>): Promise<void> => {
    if (!ctx.chat || !ctx.from || !ctx.message || ctx.chat.type !== "private") return;
    if (!isOwner(ctx)) return void await ctx.reply("This Agent bot is private.");
    try {
      const submission = await turns.submit(prepare);
      switchDelivery();
      if (!submission.accepted) {
        await ctx.reply("I’m still working on the previous message. Send /stop first if you want to interrupt it.");
      } else for (const result of submission.recovered) await deliver(result);
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
      { command: "home", description: "Show your tasks" },
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
  const token = readTelegramToken(config.homeDir);
  if (!token) throw new Error("Telegram is not connected. Run `agent telegram setup`.");
  try {
    await runGateway(token);
  } catch (error) {
    throw new Error((error instanceof Error ? error.message : String(error)).replaceAll(token, "[redacted]"));
  }
}
