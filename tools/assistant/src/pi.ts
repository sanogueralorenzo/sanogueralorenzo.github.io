import { mkdirSync } from "node:fs";
import { join } from "node:path";
import type { JsonValue } from "@earendil-works/chord";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { lazyStream, type Models, type Model, type Api, type Context, type ModelsSimpleStreamOptions } from "@earendil-works/pi-ai";
import { createCodingTools, createReadOnlyTools, formatSkillsForPrompt, ModelRuntime } from "@earendil-works/pi-coding-agent";
import { AssistantEntry, createRegistry, defineExtension, defineTool, Harness, MemoryStorage, ProviderDoc, section,
  type AnyTask, type Cursor, type Extension, type ModelRef, type Storage, type ToolRegistration } from "@earendil-works/pi-durable";
import { openNodeSqliteStorage } from "@earendil-works/pi-durable/storage/sqlite/node";
import { assistantCodexAuth } from "./codex-auth.ts";
import { ComputerUseClient } from "./computer-use.ts";
import { agentResources, type AgentRole } from "./agent-resources.ts";
import { assistantText } from "./state.ts";
import { createDelegation, delegationHooks } from "./delegation.ts";

export const defaultModel = { provider: "openai-codex", modelId: "gpt-6-luna" };
const json = <T>(value: T): T => JSON.parse(JSON.stringify(value));

function nativeTools(role: AgentRole, cwd: string): ToolRegistration[] {
  const tools = role === "session" ? [...createCodingTools(cwd), ...createReadOnlyTools(cwd).filter((tool) => tool.name !== "read")] : [];
  return tools.map((tool) => defineTool({ name: tool.name, description: tool.description, parameters: tool.parameters,
    replay: tool.name === "read" || ["grep", "find", "ls"].includes(tool.name) ? "safe" : "unsafe",
    executionMode: ["read", "grep", "find", "ls"].includes(tool.name) ? "parallel" : "sequential",
    execute: async (args, api, context) => {
      let output = "";
      const result = await tool.execute(api.callId, args, context.abortSignal, (update) => {
        const text = update.content.filter((part) => part.type === "text").map((part) => part.text).join("\n");
        if (text.startsWith(output)) api.output(text.slice(output.length));
        output = text;
      });
      return json({ content: result.content, ...(result.details !== undefined && { details: result.details as JsonValue }) });
    } }));
}

export function roleExtension(role: AgentRole, extraTools: ToolRegistration[] = [], instructions?: string[]) {
  const resources = new Map<string, ReturnType<typeof agentResources>>();
  const tools = [...nativeTools(role, process.cwd()).map((tool): ToolRegistration => ({ ...tool,
    execute: async (args, api, context) => {
      const cwd = (await api.agent(context)).cwd || process.cwd();
      return nativeTools(role, cwd).find((native) => native.name === tool.name)!.execute(args, api, context);
    } })), ...extraTools];
  return defineExtension({ name: `assistant-${role}`, tools, sections: [section("assistant", async ({ agent }) => {
      const cwd = agent.cwd || process.cwd();
      let loader = resources.get(cwd);
      if (!loader) { loader = agentResources(cwd, role, instructions); await loader.reload(); resources.set(cwd, loader); }
      const files = loader.getAgentsFiles().agentsFiles.map((file) => `Project instructions (${file.path}):\n${file.content}`);
      return [loader.getSystemPrompt(), ...files, formatSkillsForPrompt(loader.getSkills().skills)].filter(Boolean).join("\n\n");
    }, { tag: false })] });
}

export function providerModels(runtime: Models, report: (sessionId: string, data: unknown) => void = () => {}): Models {
  const active = new Set<Promise<void>>();
  return new Proxy(runtime, { get(target, key) {
    if (key !== "streamSimple") {
      const value = Reflect.get(target, key);
      return typeof value === "function" ? value.bind(target) : value;
    }
    return (model: Model<Api>, transcript: Context, options: ModelsSimpleStreamOptions = {}) => lazyStream(model, async () => {
      while (active.size >= 4) {
        options.signal?.throwIfAborted();
        await new Promise<void>((resolve, reject) => {
          const abort = () => { cleanup(); reject(options.signal!.reason); };
          const cleanup = () => options.signal?.removeEventListener("abort", abort);
          options.signal?.addEventListener("abort", abort, { once: true });
          void Promise.race(active).then(() => { cleanup(); resolve(); });
          if (options.signal?.aborted) abort();
        });
      }
      options.signal?.throwIfAborted();
      let release!: () => void;
      const occupied = new Promise<void>((resolve) => { release = resolve; });
      active.add(occupied);
      const tools = transcript.tools || transcript.messages.flatMap((message) => message.role === "system" ? message.toolsAdded || [] : []);
      const coordinator = tools.some((tool) => tool.name === "route_home");
      return (async function* () {
        try {
          yield* target.streamSimple(model, transcript, { ...options,
            onPayload: async (payload, selected) => {
              let request = await options.onPayload?.(payload, selected) ?? payload;
              if (model.provider === "openai-codex") {
                if (!request || typeof request !== "object" || Array.isArray(request)) throw new Error("Unexpected Codex request payload");
                const value = request as Record<string, unknown>;
                const search = !coordinator;
                const tools = (Array.isArray(value.tools) ? value.tools : []).filter(tool => tool?.type !== "web_search");
                request = { ...value, service_tier: "priority", tools: [...tools, ...(search ? [{ type: "web_search" }] : [])] };
              }
              return request;
            },
            onProviderStreamEvent: async (data, selected) => {
              if (options.sessionId) report(options.sessionId, data);
              await options.onProviderStreamEvent?.(data, selected);
            },
          });
        } finally { active.delete(occupied); release(); }
      })();
    });
  } });
}

export type PiOptions = { models?: Models; model?: ModelRef; extensions?: Extension[]; tasks?: AnyTask[]; storage?: Storage };
export class PiService {
  readonly harness: Harness;
  readonly models: Models;
  private readonly agentModels: Models;
  readonly model: ModelRef;
  private readonly roles: Record<AgentRole, Extension>;
  private readonly computers: Map<number, ComputerUseClient>;
  private readonly computerClosures = new Set<Promise<void>>();
  private readonly providerConversations = new Map<string, number>();
  private unsubscribe = () => {};
  onProviderEvent: (conversationId: number, data: unknown) => void = () => {};
  private constructor(harness: Harness, models: Models, agentModels: Models, model: ModelRef, roles: Record<AgentRole, Extension>, computers: Map<number, ComputerUseClient>) {
    this.harness = harness; this.models = models; this.agentModels = agentModels; this.model = model; this.roles = roles; this.computers = computers;
    this.unsubscribe = harness.subscribeCommits((publication) => {
      for (const change of publication.changes) {
        if (change.type !== "document" || !change.value || change.conversationId === undefined) continue;
        if (change.record.kind === "pi.provider") this.providerConversations.set(String(change.value.sessionId), change.conversationId);
        if (change.record.kind === "pi.live" && !change.value.run) this.closeComputer(change.conversationId);
      }
    });
  }
  static async open(dataDir: string, options: PiOptions = {}) {
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    const runtime = options.models || await ModelRuntime.create({ authPath: assistantCodexAuth(dataDir) });
    let service: PiService | undefined;
    const models = providerModels(runtime, (id, data) => {
      const conversationId = service?.providerConversations.get(id);
      if (conversationId !== undefined) service!.onProviderEvent(conversationId, data);
    });
    const model = options.model || defaultModel;
    const computers = new Map<number, ComputerUseClient>();
    const computer = new ComputerUseClient().tool();
    const computerTool = defineTool({ ...computer,
      execute: async (args, api, context) => {
        let client = computers.get(api.conversationId);
        if (!client) { client = new ComputerUseClient(); computers.set(api.conversationId, client); }
        return client.call(args.code, args.title, args.timeout_ms, context.abortSignal);
      } });
    let roles: Record<AgentRole, Extension>;
    const delegation = createDelegation(() => roles.worker, () => service!.harness);
    roles = { coordinator: roleExtension("coordinator"),
      session: defineExtension({ ...roleExtension("session", [...delegation, computerTool]), hooks: delegationHooks }),
      worker: roleExtension("worker") };
    const registry = createRegistry();
    for (const extension of [...Object.values(roles), ...(options.extensions || []), defineExtension({ name: "assistant-tasks", tasks: options.tasks })]) registry.install(extension);
    const harness = await Harness.open(options.storage || await openNodeSqliteStorage(join(dataDir, "durable.sqlite")), {
      models, registry, settings: { extensions: [], steeringMode: "one-at-a-time", followUpMode: "one-at-a-time", toolExecution: "parallel", progress: { partialIntervalMs: 16, outputIntervalMs: 16 } },
    }, BACKGROUND_CONTEXT);
    service = new PiService(harness, runtime, models, model, roles, computers);
    await harness.commit(async (tx) => {
      let cursor: Cursor | undefined;
      do {
        const page = await tx.scanConversations({}, 256, cursor);
        for (const conversation of page.items) {
          const provider = await tx.doc(ProviderDoc, conversation.id);
          service!.providerConversations.set(provider.sessionId, conversation.id);
        }
        cursor = page.next;
      } while (cursor !== undefined);
    }, BACKGROUND_CONTEXT);
    return service;
  }
  agent(role: AgentRole, cwd: string) { return { model: this.model, thinkingLevel: role === "coordinator" ? "low" as const : "high" as const, cwd, extensions: [this.roles[role]] }; }
  async utility(role: "coordinator", input: string, cwd: string, customTools: ToolRegistration[] = [], acceptedResult?: () => string | undefined) {
    const tools = customTools.map((tool) => defineTool({ name: tool.name, description: tool.description, parameters: tool.parameters,
      execute: async (args, api, context) => {
        const result = await tool.execute(args, api, context);
        // A reset ends this temporary coordinator even when its round also contains lookup tools.
        return json({ content: result.content, ...(result.details !== undefined && { details: result.details as JsonValue }), ...(acceptedResult?.() && { control: { handoff: "" } }) });
      } }));
    const registry = createRegistry();
    const extension = roleExtension(role, tools);
    registry.install(extension);
    const harness = await Harness.open(new MemoryStorage(), { models: this.agentModels, registry }, BACKGROUND_CONTEXT);
    try {
      const root = await harness.root(BACKGROUND_CONTEXT, { agent: { model: this.model, thinkingLevel: "low", cwd, extensions: [extension] } });
      const settled = await (await root.submit({ type: "input", content: input }, BACKGROUND_CONTEXT)).wait(BACKGROUND_CONTEXT);
      if (acceptedResult?.()) return acceptedResult()!;
      if (settled.status !== "done" || settled.type !== "input") throw new Error("Coordinator did not choose a destination");
      const entry = await root.commit((tx) => tx.entry(AssistantEntry, settled.answer), BACKGROUND_CONTEXT);
      return assistantText(entry?.model?.[0] || {});
    } finally { await harness.close(BACKGROUND_CONTEXT); }
  }
  closeComputer(id: number) {
    const client = this.computers.get(id);
    this.computers.delete(id);
    if (!client) return;
    const closing = client.close();
    this.computerClosures.add(closing);
    // Retain a failed close for shutdown to report; completed turn results must stay completed.
    void closing.then(() => this.computerClosures.delete(closing), () => {});
  }
  async close() {
    await this.harness.close(BACKGROUND_CONTEXT);
    this.unsubscribe();
    for (const id of this.computers.keys()) this.closeComputer(id);
    await Promise.all(this.computerClosures);
  }
}
