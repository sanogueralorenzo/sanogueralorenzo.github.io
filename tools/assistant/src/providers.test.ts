import assert from "node:assert/strict";
import { test, type TestContext } from "node:test";
import { mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { once } from "node:events";
import { createModels, InMemoryCredentialStore, type OAuthAuth, type OAuthCredential } from "@earendil-works/pi-ai";
import { anthropicProvider } from "@earendil-works/pi-ai/providers/anthropic";
import { openaiCodexProvider } from "@earendil-works/pi-ai/providers/openai-codex";
import { fauxAssistantMessage, fauxProvider, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import type { ConversationId } from "@earendil-works/pi-durable";
import { Providers, assistantModels, type ProviderSnapshot } from "./providers.ts";
import { Assistant } from "./assistant.ts";
import { createAssistantServer } from "./http-server.ts";

const credential = (): OAuthCredential => ({ type: "oauth", access: "private-access", refresh: "private-refresh", expires: Date.now() + 3600_000 });
function directory(t: TestContext) {
  const dir = mkdtempSync(join(tmpdir(), "assistant-providers-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}
function fixture(t: TestContext, login?: OAuthAuth["login"]) {
  const dir = directory(t);
  const credentials = new InMemoryCredentialStore();
  const models = createModels({ credentials, authContext: { env: async () => undefined, fileExists: async () => false } });
  for (const provider of [openaiCodexProvider(), anthropicProvider()]) models.setProvider({ ...provider,
    auth: { oauth: { ...provider.auth.oauth!, login: login || (async () => credential()) } } });
  const providers = new Providers(dir, models);
  t.after(() => providers.close());
  return { dir, credentials, models, providers };
}
async function waitFor(providers: Providers, condition: (state: ProviderSnapshot) => boolean) {
  const deadline = Date.now() + 5000;
  while (true) {
    const state = await providers.snapshot();
    if (condition(state)) return state;
    assert.ok(Date.now() < deadline, "Timed out waiting for provider state");
    await delay(2);
  }
}

test("both Pi login catalogs load without a Codex CLI account or existing credentials", async t => {
  const dir = directory(t);
  const models = await assistantModels(dir);
  const providers = new Providers(dir, models);
  t.after(() => providers.close());
  const state = await providers.snapshot();
  assert.deepEqual(state.providers.map(item => item.name), ["Codex", "Claude"]);
  for (const provider of state.providers) {
    assert.ok(provider.models.some(model => model.id === provider.defaultModel));
    assert.ok(models.getProvider(provider.id)?.auth.oauth?.login);
  }
  assert.equal((statSync(join(dir, "auth.json")).mode & 0o777), 0o600);
  assert.equal(readFileSync(join(dir, "auth.json"), "utf8"), "{}");
});

test("OAuth prompts, notifications, credential storage, and selected model survive the full login flow", async t => {
  const f = fixture(t, async interaction => {
    assert.equal(await interaction.prompt({ type: "select", message: "Login method", options: [{ id: "browser", label: "Browser" }] }), "browser");
    interaction.notify({ type: "auth_url", url: "https://login.example/authorize", instructions: "Open sign-in" });
    assert.equal(await interaction.prompt({ type: "manual_code", message: "Paste code" }), "test-code");
    return credential();
  });
  const id = f.providers.startLogin("anthropic");
  let state = await waitFor(f.providers, state => !!state.login?.prompt);
  assert.equal(state.login!.id, id);
  assert.throws(() => f.providers.startLogin("openai-codex"), /Finish or cancel/);
  assert.throws(() => f.providers.respond(id, state.login!.prompt!.id, "invalid"), /listed/);
  const firstPrompt = state.login!.prompt!.id;
  f.providers.respond(id, firstPrompt, "browser");
  state = await waitFor(f.providers, state => state.login?.prompt?.type === "manual_code");
  assert.equal(state.login!.url, "https://login.example/authorize");
  assert.throws(() => f.providers.respond(id, firstPrompt, "stale-code"), /ended/);
  f.providers.respond(id, state.login!.prompt!.id, "test-code");
  state = await waitFor(f.providers, state => state.login?.status === "done");
  assert.equal(state.selected.provider, "anthropic");
  assert.ok(state.providers.find(item => item.id === "anthropic")?.connected);
  assert.doesNotMatch(JSON.stringify(state), /private-access|private-refresh|test-code/);
  assert.equal(state.login!.url, undefined);
  assert.equal((await f.credentials.read("anthropic"))?.type, "oauth");
  await f.providers.select("anthropic", "claude-haiku-5-5");
  assert.deepEqual(new Providers(f.dir, f.models).model, { provider: "anthropic", modelId: "claude-haiku-5-5" });
});

test("Pi persists and reloads both provider credentials in Assistant's private auth file", async t => {
  const dir = directory(t);
  const models = await assistantModels(dir);
  const providers = new Providers(dir, models);
  t.after(() => providers.close());
  for (const provider of ["openai-codex", "anthropic"]) {
    models.getProvider(provider)!.auth.oauth!.login = async () => credential();
    providers.startLogin(provider);
    await waitFor(providers, state => state.login?.status === "done");
  }
  const stored = JSON.parse(readFileSync(join(dir, "auth.json"), "utf8"));
  assert.equal(stored["openai-codex"].access, "private-access");
  assert.equal(stored.anthropic.refresh, "private-refresh");
  const reopened = new Providers(dir, await assistantModels(dir));
  t.after(() => reopened.close());
  const state = await reopened.snapshot();
  assert.ok(state.providers.every(provider => provider.connected));
  assert.equal(state.selected.provider, "anthropic");
  assert.doesNotMatch(JSON.stringify(state), /private-access|private-refresh/);
});

test("callback completion cancels the manual prompt and rejects a late pasted code", async t => {
  let callback!: () => void;
  const arrived = new Promise<void>(resolve => { callback = resolve; });
  const f = fixture(t, async interaction => {
    const controller = new AbortController();
    const prompt = interaction.prompt({ type: "manual_code", message: "Code", signal: controller.signal });
    await Promise.race([prompt, arrived]);
    controller.abort();
    return credential();
  });
  const id = f.providers.startLogin("openai-codex");
  const pending = await waitFor(f.providers, state => !!state.login?.prompt);
  callback();
  await waitFor(f.providers, state => state.login?.status === "done");
  assert.throws(() => f.providers.respond(id, pending.login!.prompt!.id, "late"), /ended/);
});

test("cancel and shutdown release login prompts; failures never publish token exchange details", async t => {
  const f = fixture(t, interaction => interaction.prompt({ type: "manual_code", message: "Code" }).then(() => credential()));
  const id = f.providers.startLogin("anthropic");
  const state = await waitFor(f.providers, state => !!state.login?.prompt);
  await f.providers.cancelLogin(id);
  assert.equal((await f.providers.snapshot()).login?.status, "cancelled");
  assert.throws(() => f.providers.respond(id, state.login!.prompt!.id, "late"), /ended/);
  f.providers.startLogin("openai-codex");
  await waitFor(f.providers, state => !!state.login?.prompt);
  await f.providers.close();
  assert.equal((await f.providers.snapshot()).login?.status, "cancelled");
  const failed = fixture(t, async () => { throw new Error("private-access private-refresh"); });
  failed.providers.startLogin("anthropic");
  const failure = await waitFor(failed.providers, state => state.login?.status === "failed");
  assert.doesNotMatch(JSON.stringify(failure), /private-access|private-refresh/);
  assert.match(failure.login!.message!, /try again/);
});

test("selection rejects disconnected providers and unknown models; sign-out affects only its provider", async t => {
  const f = fixture(t);
  await assert.rejects(f.providers.select("anthropic"), /Sign in/);
  assert.throws(() => f.providers.startLogin("other"), /Codex or Claude/);
  for (const provider of ["openai-codex", "anthropic"]) {
    f.providers.startLogin(provider);
    await waitFor(f.providers, state => state.login?.status === "done");
  }
  await assert.rejects(f.providers.select("anthropic", "missing"), /listed|list/);
  await f.providers.logout("anthropic");
  const state = await f.providers.snapshot();
  assert.equal(state.providers.find(item => item.id === "anthropic")?.connected, false);
  assert.equal(state.providers.find(item => item.id === "openai-codex")?.connected, true);
});

test("switching providers changes new tasks while existing conversations keep their model across restart", async t => {
  const dir = directory(t);
  const models = createModels();
  const codex = fauxProvider({ provider: "openai-codex", models: [{ id: "gpt-6-luna" }], tokensPerSecond: 100000 });
  const claude = fauxProvider({ provider: "anthropic", models: [{ id: "claude-sonnet-5-5" }], tokensPerSecond: 100000 });
  models.setProvider(codex.provider); models.setProvider(claude.provider);
  const route = (title: string) => fauxAssistantMessage(fauxToolCall("route_home", { mode: "start", title, cwd: dir }), { stopReason: "toolUse" });
  // Suggestions are tool-free and may arrive between fixture responses.
  codex.setResponses([route("Codex task"), fauxAssistantMessage("Codex result"), fauxAssistantMessage("NONE")]);
  let app = await Assistant.open(dir, dir, { models });
  t.after(() => app.shutdown());
  await app.submitHome("First task"); await app.pi.harness.waitForIdle(BACKGROUND_CONTEXT);
  const first = app.snapshot().sessions[0];
  await app.pi.providers.select("anthropic");
  claude.setResponses([route("Claude task"), fauxAssistantMessage("Claude result"), fauxAssistantMessage("NONE")]);
  await app.submitHome("Second task"); await app.pi.harness.waitForIdle(BACKGROUND_CONTEXT);
  const second = app.snapshot().sessions[1];
  for (const [record, provider] of [[first, "openai-codex"], [second, "anthropic"]] as const) {
    const conversation = await app.pi.harness.conversation(record.conversationId as ConversationId, BACKGROUND_CONTEXT);
    assert.equal((await conversation!.agent(BACKGROUND_CONTEXT)).model?.provider, provider);
  }
  await app.shutdown();
  app = await Assistant.open(dir, dir, { models });
  assert.equal(app.pi.model.provider, "anthropic");
  codex.setResponses([fauxAssistantMessage("Codex follow-up"), fauxAssistantMessage("NONE")]);
  await app.submitSession(first.id, "Continue first task"); await app.pi.harness.waitForIdle(BACKGROUND_CONTEXT);
  assert.match(app.transcript(first.id).messages.at(-1)!.text, /Codex follow-up/);
});

test("provider HTTP endpoints expose resumable login state, validate origin, and publish updates over SSE", async t => {
  const f = fixture(t, interaction => interaction.prompt({ type: "manual_code", message: "Code" }).then(() => credential()));
  const app = await Assistant.open(f.dir, f.dir, { models: f.models });
  t.after(() => app.shutdown());
  const http = createAssistantServer(app);
  http.server.listen(0, "127.0.0.1"); await once(http.server, "listening");
  t.after(http.close);
  const address = http.server.address(); assert.ok(address && typeof address === "object");
  const url = `http://127.0.0.1:${address.port}`;
  const post = (path: string, body: unknown, origin?: string) => fetch(`${url}/api/providers/${path}`, { method: "POST",
    headers: { "content-type": "application/json", ...(origin && { origin }) }, body: JSON.stringify(body) });
  assert.equal((await post("login", { provider: "anthropic" }, "https://other.example")).status, 403);
  const result = await post("login", { provider: "anthropic" }); assert.equal(result.status, 202);
  const { loginId } = await result.json();
  const pending = await waitFor(app.pi.providers, state => !!state.login?.prompt);
  const controller = new AbortController(); t.after(() => controller.abort());
  const stream = await fetch(`${url}/api/events`, { signal: controller.signal });
  const reader = stream.body!.getReader(); let events = "";
  while (!events.includes('"type":"providers"')) events += new TextDecoder().decode((await reader.read()).value);
  assert.ok(events.includes(loginId));
  assert.doesNotMatch(events, /private-access|private-refresh/);
  assert.equal((await post("respond", { loginId, promptId: "wrong", value: "code" })).status, 400);
  assert.equal((await post("respond", { loginId, promptId: pending.login!.prompt!.id, value: "code" })).status, 202);
  await waitFor(app.pi.providers, state => state.login?.status === "done");
  const state = await (await fetch(`${url}/api/providers`)).json();
  assert.equal(state.selected.provider, "anthropic");
  assert.doesNotMatch(JSON.stringify(state), /private-access|private-refresh/);
  controller.abort();
});
