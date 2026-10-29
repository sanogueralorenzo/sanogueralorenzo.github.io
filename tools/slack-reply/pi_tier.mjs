const fail = message => { throw new Error(`Slack Reply tier: ${message}`); };
const opusModel = id => id.replace(/-\d{8}$|-\d{4}-\d{2}-\d{2}$/, "");
const fastOpus = new Set(["claude-opus-5-5", "claude-opus-5", "claude-opus-4-8"]);

export function tierPayload(model, payload, tier) {
  if (!["default", "fast"].includes(tier)) fail("tier must be default or fast");
  if (!model) fail("choose a model before configuring its tier");
  if (["openai", "openai-codex", "xai"].includes(model.provider) &&
      ["openai-responses", "openai-codex-responses", "openai-completions"].includes(model.api)) {
    return { ...payload, service_tier: tier === "fast" ? "priority" : "default" };
  }
  if (model.provider === "google" && model.api === "google-generative-ai") {
    const { serviceTier: _tier, ...config } = payload.config || {};
    return { ...payload, config: { ...config, ...(tier === "fast" && { serviceTier: "priority" }) } };
  }
  if (model.provider === "anthropic" && model.api === "anthropic-messages") {
    if (tier === "fast" && !fastOpus.has(opusModel(model.id))) fail(`fast mode is unsupported for ${model.id}; choose a supported Opus model`);
    const { speed: _speed, ...request } = payload;
    return { ...request, ...(tier === "fast" && { speed: "fast" }) };
  }
  if (tier === "fast") fail(`fast mode is unsupported for ${model.provider}/${model.id}`);
  return payload;
}

export default function tierExtension(pi) {
  pi.registerFlag("slack-reply-tier", { type: "string", description: "Slack Reply service tier" });
  pi.on("before_provider_request", (event, ctx) => {
    try {
      return tierPayload(ctx.model, event.payload, pi.getFlag("slack-reply-tier"));
    } catch (error) {
      ctx.abort();
      throw error;
    }
  });
  pi.on("before_provider_headers", (event, ctx) => {
    if (ctx.model?.provider !== "anthropic" || ctx.model.api !== "anthropic-messages") return;
    const betas = (event.headers["anthropic-beta"] || "").split(",").filter(value => value && value !== "fast-mode-2026-02-01");
    if (pi.getFlag("slack-reply-tier") === "fast" && fastOpus.has(opusModel(ctx.model.id)) &&
        opusModel(ctx.model.id) !== "claude-opus-5-5") betas.push("fast-mode-2026-02-01");
    event.headers["anthropic-beta"] = betas.length ? betas.join(",") : null;
  });
}
