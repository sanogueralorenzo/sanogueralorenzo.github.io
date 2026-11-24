import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { ImageContent } from "@earendil-works/pi-ai";
import { startCli } from "./process.ts";

export const turnSchema = {
  type: "object",
  properties: {
    text: { type: "string" },
    calls: { type: "array", items: {
      type: "object",
      properties: { name: { type: "string" }, arguments: { type: "string" } },
      required: ["name", "arguments"],
      additionalProperties: false,
    } },
  },
  required: ["text", "calls"],
  additionalProperties: false,
};

export type Turn = {
  cwd: string;
  instructions: string;
  transcript: string;
  images: ImageContent[];
  model: string;
  effort?: string;
  search: boolean;
  fast: boolean;
  signal: AbortSignal;
  progress: (key: string, delta: string) => void;
  source: (source: unknown) => void;
};

export type CliUsage = {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation_input_tokens?: number;
  cached_input_tokens?: number;
  cache_read_tokens?: number;
  thinking_tokens?: number;
  total_tokens?: number;
};

export type TurnResult = { output: unknown; usage?: CliUsage; totalCost?: number; id?: string };

async function imageFiles(turn: Turn) {
  const extensions: Record<string, string> = { "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp" };
  return await Promise.all(turn.images.map(async (image, index) => {
    const extension = extensions[image.mimeType];
    if (!extension) throw new Error("Unsupported image type");
    const path = join(turn.cwd, `agent-image-${index + 1}.${extension}`);
    await writeFile(path, Buffer.from(image.data, "base64"), { signal: turn.signal, mode: 0o600 });
    return path;
  }));
}

export async function claudeTurn(turn: Turn): Promise<TurnResult> {
  const tools = turn.search ? "WebSearch,WebFetch" : "";
  const prompt = join(turn.cwd, "claude-prompt.md");
  await writeFile(prompt, turn.instructions, { signal: turn.signal, mode: 0o600 });
  const args = ["-p", "--model", turn.model, "--system-prompt-file", prompt, "--strict-mcp-config", "--restricted",
    "--setting-sources", "", "--settings", JSON.stringify({ disableAllHooks: true, fastMode: turn.fast }),
    "--no-session-persistence", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
    "--include-partial-messages", "--permission-mode", "dontAsk", "--tools", tools,
    ...(tools ? ["--allowed-tools", tools] : []), "--json-schema", JSON.stringify(turnSchema),
    ...(turn.effort && turn.effort !== "none" ? ["--effort", turn.effort] : ["--effort", "low"])];
  const cli = startCli("claude", args, turn.cwd, turn.signal);
  const events = cli.events();
  try {
    cli.send({ type: "user", message: { role: "user", content: [{ type: "text", text: turn.transcript },
      ...turn.images.map(image => ({ type: "image", source: { type: "base64", media_type: image.mimeType, data: image.data } }))] } });
    cli.end();
    let messageId: string | undefined;
    let blockIndex: number | undefined;
    let response: TurnResult | undefined;
    for await (const event of events) {
      if (event.type === "stream_event" && !event.parent_tool_use_id) {
        const item = event.event;
        if (item.type === "message_start") { messageId = item.message.id; blockIndex = undefined; }
        if (item.type === "content_block_start" && item.content_block.name === "StructuredOutput") blockIndex = item.index;
        if (item.type === "content_block_delta") {
          if (blockIndex === item.index && item.delta.type === "input_json_delta") {
            turn.progress(messageId || "response", item.delta.partial_json);
          }
          if (item.delta.type === "citations_delta") turn.source(item.delta.citation);
        }
      } else if (event.type === "result" && !event.is_error && event.subtype === "success") {
        response = { output: event.structured_output, usage: event.usage, totalCost: event.total_cost_usd, id: messageId };
      }
    }
    await cli.result();
    if (!response) throw new Error("Claude Code did not complete the turn");
    return response;
  } finally { await cli.stop(); }
}

export async function googleTurn(turn: Turn): Promise<TurnResult> {
  const images = await imageFiles(turn);
  const allowedTools = [...(turn.search ? ["search_web", "read_url_content"] : []), ...(images.length ? ["view_file"] : [])];
  const agents = join(turn.cwd, ".agents", "agents");
  await mkdir(agents, { recursive: true });
  await writeFile(join(agents, "agent-turn.md"), [
    "---", "name: agent-turn", "description: Return one response for Agent.",
    `tools: ${JSON.stringify(allowedTools)}`, "subagent: false", "commandExecutionPolicy: off",
    "mcpServers: []", "skills: []", "plugins: []", "---", turn.instructions,
  ].join("\n"), { signal: turn.signal, mode: 0o600 });
  const settings = JSON.stringify({ allowNonWorkspaceAccess: false, toolPermission: "strict", permissions: {
    allow: [...(turn.search ? ["read_url(*)"] : []), ...images.map(path => `read_file(${path})`)],
    deny: ["command(*)", "write_file(*)", "mcp(*)", ...(turn.search ? [] : ["read_url(*)"]), ...(images.length ? [] : ["read_file(*)"])],
  } });
  const effort = turn.effort && turn.effort !== "none" ? turn.effort : "low";
  const cli = startCli("agy", ["--agent", "agent-turn", "--model", turn.model, "--effort", effort, "--settings", settings,
    "--input-format", "stream-json", "--output-format", "stream-json", "--json-schema", JSON.stringify(turnSchema),
    "--print-timeout", "10m"], turn.cwd, turn.signal);
  const events = cli.events();
  try {
    const attachments = images.map((path, index) => `[Agent image ${index + 1}]: ${path}`).join("\n");
    cli.send({ event: "user", message: { content: attachments
      ? `${turn.transcript}\n\nUse view_file to inspect relevant image attachments.\n${attachments}`
      : turn.transcript } });
    cli.end();
    let response: TurnResult | undefined;
    for await (const event of events) {
      const step = event.step_update;
      if (event.event === "step_update" && step?.step_type === "agent_response" && typeof step.text_delta === "string") {
        turn.progress(String(step.step_index), step.text_delta);
      }
      if (event.event === "result" && event.result?.status === "SUCCESS") {
        const result = event.result;
        response = { output: result.structured_output, usage: result.usage, id: result.conversation_id };
      }
    }
    await cli.result();
    if (!response) throw new Error("Antigravity did not complete the turn");
    return response;
  } finally { await cli.stop(); }
}
