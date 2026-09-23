import type { Socket } from "node:net";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { ensureDaemon, getSourceId, request } from "./protocol.mjs";

type Entry = { source?: string; seq?: number; type: string; text: string; title?: string; jobId?: string; at?: string };

export default function (pi: ExtensionAPI) {
  let source = "";
  let lastSeq = 0;
  let listener: Socket | null = null;
  let stopped = true;
  let reconnect: ReturnType<typeof setTimeout> | undefined;

  pi.registerEntryRenderer<Entry>("pi-agent-update", (entry, { expanded }, theme) => {
    const data = entry.data;
    const label = data?.type === "routing" ? "You" : data?.title || "Agent";
    const body = `${theme.fg("accent", label)}  ${data?.text || ""}`;
    const detail = expanded && data?.jobId ? `\n${theme.fg("dim", `Task ${data.jobId}`)}` : "";
    return new Text(`${body}${detail}`, 0, 0);
  });

  function add(entry: Entry) {
    if (entry.seq !== undefined) {
      if (entry.seq <= lastSeq) return;
      lastSeq = entry.seq;
    }
    pi.appendEntry("pi-agent-update", entry);
  }

  async function listen(ctx: ExtensionContext) {
    if (stopped) return;
    try {
      const socket = await ensureDaemon();
      if (stopped) return socket.destroy();
      listener = socket;
      let buffer = "";
      socket.on("data", (chunk) => {
        buffer += chunk.toString();
        let newline: number;
        while ((newline = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, newline);
          buffer = buffer.slice(newline + 1);
          try {
            const event = JSON.parse(line);
            if (event.kind === "event" && typeof event.seq === "number") {
              if (["routing", "progress", "complete", "failed", "interrupted", "cancelled", "reporter_failed"].includes(event.type)) add(event);
              else lastSeq = Math.max(lastSeq, event.seq);
              if (!event.replay && ["complete", "failed", "interrupted", "cancelled"].includes(event.type)) {
                ctx.ui.notify(event.text, event.type === "complete" ? "info" : "warning");
              }
            }
          } catch { /* A malformed event must not end the listener. */ }
        }
      });
      socket.on("close", () => {
        if (listener === socket) listener = null;
        if (!stopped) reconnect = setTimeout(() => void listen(ctx), 500);
      });
      socket.on("error", () => socket.destroy());
      socket.write(`${JSON.stringify({ type: "subscribe", source, after: lastSeq })}\n`);
    } catch (error) {
      ctx.ui.notify(`Agent listener: ${String(error)}`, "warning");
      if (!stopped) reconnect = setTimeout(() => void listen(ctx), 2000);
    }
  }

  pi.on("session_start", async (_event, ctx) => {
    source = getSourceId();
    lastSeq = 0;
    for (const entry of ctx.sessionManager.getEntries()) {
      if (entry.type === "custom" && entry.customType === "pi-agent-update") {
        const data = entry.data as Entry | undefined;
        if (data?.source === source && typeof data.seq === "number") lastSeq = Math.max(lastSeq, data.seq);
      }
    }
    stopped = false;
    void listen(ctx);
  });

  pi.on("session_shutdown", async () => {
    stopped = true;
    if (reconnect) clearTimeout(reconnect);
    listener?.destroy();
    listener = null;
  });

  pi.on("input", async (event, ctx) => {
    if (event.source === "extension" || !event.text.trim()) return { action: "continue" };
    if (event.images?.length) {
      ctx.ui.notify("Image requests are handled by the current Pi session.", "info");
      return { action: "continue" };
    }
    try {
      await request({ type: "dispatch", source, cwd: ctx.cwd, text: event.text.trim() });
    } catch (error) {
      add({ type: "failed", title: "Dispatch failed", text: String(error) });
    }
    return { action: "handled" };
  });

  pi.registerCommand("agent-jobs", {
    description: "Show delegated tasks for this Pi conversation",
    handler: async (_args, ctx) => {
      try {
        const result = await request({ type: "list", source }) as { jobs: { id: string; title: string; state: string }[] };
        ctx.ui.notify(result.jobs.length ? result.jobs.map((job) => `${job.id} ${job.state}: ${job.title}`).join("\n") : "No delegated tasks.", "info");
      } catch (error) { ctx.ui.notify(String(error), "error"); }
    },
  });
  pi.registerCommand("agent-followup", {
    description: "Send a follow-up directly to a delegated task: /agent-followup TASK_ID message",
    handler: async (args, ctx) => {
      const [jobId, ...rest] = args.trim().split(/\s+/);
      const text = rest.join(" ").trim();
      if (!jobId || !text) return ctx.ui.notify("Usage: /agent-followup TASK_ID message", "warning");
      try { await request({ type: "followup", source, jobId, text }); }
      catch (error) { ctx.ui.notify(String(error), "error"); }
    },
  });
  pi.registerCommand("agent-cancel", {
    description: "Cancel a delegated task: /agent-cancel TASK_ID",
    handler: async (args, ctx) => {
      const jobId = args.trim();
      if (!jobId) return ctx.ui.notify("Usage: /agent-cancel TASK_ID", "warning");
      try { await request({ type: "cancel", source, jobId }); }
      catch (error) { ctx.ui.notify(String(error), "error"); }
    },
  });
  pi.registerCommand("agent-resume", {
    description: "Resume an interrupted delegated task: /agent-resume TASK_ID",
    handler: async (args, ctx) => {
      const jobId = args.trim();
      if (!jobId) return ctx.ui.notify("Usage: /agent-resume TASK_ID", "warning");
      try { await request({ type: "resume", source, jobId }); }
      catch (error) { ctx.ui.notify(String(error), "error"); }
    },
  });
  pi.registerCommand("agent-direct", {
    description: "Send a message to this Pi session instead of delegating it",
    handler: async (args, ctx) => {
      if (!args.trim()) return ctx.ui.notify("Usage: /agent-direct message", "warning");
      pi.sendUserMessage(args.trim(), { deliverAs: "followUp" });
    },
  });
}
