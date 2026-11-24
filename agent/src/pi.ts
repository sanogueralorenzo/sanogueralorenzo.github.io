import { mkdirSync } from "node:fs";
import { join } from "node:path";
import type { Context as TaskContext, JsonValue } from "@earendil-works/chord";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { lazyStream, type Models, type Model, type Api, type Context, type ModelsSimpleStreamOptions } from "@earendil-works/pi-ai";
import { createCodingTools, createReadOnlyTools, formatSkillsForPrompt } from "@earendil-works/pi-coding-agent";
import { AssistantEntry, createRegistry, defineExtension, defineTool, Harness, MemoryStorage, section,
  LiveDoc, ProviderDoc, type AnyTask, type ConversationId, type Extension, type ModelRef, type Storage, type ToolRegistration } from "@earendil-works/pi-durable";
import { openNodeSqliteStorage } from "@earendil-works/pi-durable/storage/sqlite/node";
import { Providers, utilityAgent } from "./providers.ts";
import { cliModels } from "./cli/models.ts";
import { CodexTurns } from "./cli/codex.ts";
import { ComputerUseClient } from "./computer-use.ts";
import { agentResources, type AgentRole } from "./agent-resources.ts";
import { agentText } from "./state.ts";
import { createDelegation, delegationHooks } from "./delegation.ts";
import { workingNotes, workingNotesSection } from "./working-notes.ts";
import { workingDirectory, workingDirectoryHook } from "./working-directory.ts";

const json = <T>(value: T): T => JSON.parse(JSON.stringify(value));

function nativeTools(role: AgentRole, cwd: string): ToolRegistration[] {
  const tools = role === "dispatcher" ? [] : role === "worker" ? [...createCodingTools(cwd), ...createReadOnlyTools(cwd).filter((tool) => tool.name !== "read")]
    : createReadOnlyTools(cwd);
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
      return json({ output: result.content, ...(result.details !== undefined && { details: result.details as JsonValue }) });
    } }));
}

export function roleExtension(role: AgentRole, extraTools: ToolRegistration[] = [], instructions?: string[]) {
  const resources = new Map<number, { cwd: string; loader: ReturnType<typeof agentResources> }>();
  const tools = [...nativeTools(role, process.cwd()).map((tool): ToolRegistration => ({ ...tool,
    execute: async (args, api, context) => {
      const cwd = (await api.agent(context)).cwd || process.cwd();
      return nativeTools(role, cwd).find((native) => native.name === tool.name)!.execute(args, api, context);
    } })), ...extraTools, ...(!["router", "dispatcher"].includes(role) ? [workingNotes, workingDirectory] : [])];
  return defineExtension({ name: `agent-${role}`, tools, hooks: !["router", "dispatcher"].includes(role) ? [workingDirectoryHook, ...delegationHooks] : [], sections: [section("agent", async ({ agent, conversationId }) => {
      const cwd = agent.cwd || process.cwd();
      let resource = resources.get(conversationId);
      if (!resource || resource.cwd !== cwd) {
        const loader = agentResources(cwd, role, instructions);
        await loader.reload(); resource = { cwd, loader }; resources.set(conversationId, resource);
      }
      const { loader } = resource;
      const files = loader.getAgentsFiles().agentsFiles.map((file) => `Project instructions (${file.path}):\n${file.content}`);
      return [loader.getSystemPrompt(), `Working directory: ${cwd}`, ...files, formatSkillsForPrompt(loader.getSkills().skills)].filter(Boolean).join("\n\n");
    }, { tag: false }), ...(!["router", "dispatcher"].includes(role) ? [workingNotesSection] : [])] });
}

export function providerModels(runtime: Models): Models {
  const maxWorkRequests = 8;
  const active = new Set<Promise<void>>();
  return new Proxy(runtime, { get(target, key) {
    if (key !== "streamSimple") {
      const value = Reflect.get(target, key);
      return typeof value === "function" ? value.bind(target) : value;
    }
    return (model: Model<Api>, transcript: Context, options: ModelsSimpleStreamOptions = {}) => lazyStream(model, async () => {
      const tools = transcript.tools || transcript.messages.flatMap((message) => message.role === "system" ? message.toolsAdded || [] : []);
      const routing = tools.some((tool) => tool.name === "route_home");
      const scheduling = routing || tools.some((tool) => tool.name === "dispatch_message");
      // Keep dispatch responsive under execution load, and Home routing responsive under dispatch load.
      const limit = maxWorkRequests + (routing ? 2 : scheduling ? 1 : 0);
      while (active.size >= limit) {
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
      return (async function* () {
        try {
          yield* target.streamSimple(model, transcript, options);
        } finally { active.delete(occupied); release(); }
      })();
    });
  } });
}

export type PiOptions = { models?: Models; model?: ModelRef; extensions?: Extension[]; tasks?: AnyTask[]; storage?: Storage };
export class PiService {
  readonly harness: Harness;
  readonly models: Models;
  readonly providers: Providers;
  private readonly fixedModel?: ModelRef;
  private readonly roles: Record<AgentRole, Extension>;
  private readonly computers: Map<number, ComputerUseClient>;
  private readonly codex?: CodexTurns;
  private readonly computerClosures = new Set<Promise<void>>();
  private unsubscribe = () => {};
  private constructor(harness: Harness, models: Models, providers: Providers, fixedModel: ModelRef | undefined, roles: Record<AgentRole, Extension>, computers: Map<number, ComputerUseClient>, codex?: CodexTurns) {
    this.harness = harness; this.models = models; this.providers = providers; this.fixedModel = fixedModel; this.roles = roles; this.computers = computers; this.codex = codex;
    this.unsubscribe = harness.subscribeCommits((publication) => {
      for (const change of publication.changes) {
        if (change.type !== "document" || !change.value || change.conversationId === undefined) continue;
        if (change.record.kind === "pi.live" && !change.value.run) {
          this.closeComputer(change.conversationId);
          void this.closeCodex(harness, change.conversationId).catch(() => {});
        }
      }
    });
  }
  static async open(dataDir: string, options: PiOptions = {}) {
    mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    const providers = new Providers(dataDir);
    if (!options.models) await providers.refresh();
    let service: PiService | undefined;
    const codex = options.models ? undefined : new CodexTurns();
    const models = providerModels(options.models || cliModels(provider => providers.fastEnabled(provider), codex));
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
    roles = { router: roleExtension("router"), dispatcher: roleExtension("dispatcher"),
      coordinator: roleExtension("coordinator", delegation),
      worker: roleExtension("worker", [...delegation, computerTool]) };
    const registry = createRegistry();
    for (const extension of [...Object.values(roles), ...(options.extensions || []), defineExtension({ name: "agent-tasks", tasks: options.tasks })]) registry.install(extension);
    const harness = await Harness.open(options.storage || await openNodeSqliteStorage(join(dataDir, "durable.sqlite")), {
      models, registry, settings: { extensions: [], steeringMode: "one-at-a-time", followUpMode: "one-at-a-time", toolExecution: "parallel", progress: { partialIntervalMs: 16, outputIntervalMs: 16 } },
    }, BACKGROUND_CONTEXT);
    service = new PiService(harness, models, providers, options.model, roles, computers, codex);
    return service;
  }
  get model(): ModelRef { return this.fixedModel || this.providers.model; }
  async availableModel(preferred?: ModelRef) {
    if (this.fixedModel) return preferred || this.fixedModel;
    await this.providers.refresh();
    if (preferred && this.providers.usable(preferred)) return preferred;
    const model = this.model;
    if (!this.providers.usable(model)) throw new Error("Sign in to Codex, Claude Code, or Google Antigravity on the Agent host");
    return model;
  }
  agent(role: AgentRole, cwd: string) {
    const utility = ["router", "dispatcher"].includes(role);
    return { ...(utility ? utilityAgent(this.model) : { model: this.model, thinkingLevel: "high" as const }), cwd, extensions: [this.roles[role]] };
  }
  async utility(role: "router" | "dispatcher", input: string, cwd: string, customTools: ToolRegistration[] = [], acceptedResult?: () => string | undefined, context: TaskContext = BACKGROUND_CONTEXT) {
    await this.availableModel();
    const tools = customTools.map((tool) => defineTool({ name: tool.name, description: tool.description, parameters: tool.parameters,
      execute: async (args, api, context) => {
        const result = await tool.execute(args, api, context);
        // A reset ends this temporary router even when its round also contains lookup tools.
        return json({ ...result, ...(acceptedResult?.() && { control: { handoff: "" } }) });
      } }));
    const registry = createRegistry();
    const extension = roleExtension(role, tools);
    registry.install(extension);
    const harness = await Harness.open(new MemoryStorage(), { models: this.models, registry }, context);
    let rootId: ConversationId | undefined;
    try {
      const root = await harness.root(context, { agent: { ...this.agent(role, cwd), extensions: [extension] } });
      rootId = root.id;
      const settled = await (await root.submit({ type: "input", content: input }, context)).wait(context);
      if (acceptedResult?.()) return acceptedResult()!;
      if (settled.status !== "done" || settled.type !== "input") throw new Error("Router did not choose a destination");
      const entry = await root.commit((tx) => tx.entry(AssistantEntry, settled.answer), context);
      return agentText(entry?.model?.[0] || {});
    } finally {
      try { if (rootId !== undefined) await this.closeCodex(harness, rootId); }
      finally { await harness.close(BACKGROUND_CONTEXT); }
    }
  }
  private async closeCodex(harness: Harness, conversationId: ConversationId) {
    if (!this.codex) return;
    const provider = await harness.snapshot(ProviderDoc, conversationId, BACKGROUND_CONTEXT);
    const live = await harness.snapshot(LiveDoc, conversationId, BACKGROUND_CONTEXT);
    if (provider && !live?.run) await this.codex.closeSession(provider.sessionId);
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
    await this.providers.close();
    await this.harness.close(BACKGROUND_CONTEXT);
    this.unsubscribe();
    await this.codex?.close();
    for (const id of this.computers.keys()) this.closeComputer(id);
    await Promise.all(this.computerClosures);
  }
}
