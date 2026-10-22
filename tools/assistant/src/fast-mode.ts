import type { Api, Model } from "@earendil-works/pi-ai";

// Pi has no fast-mode capability metadata. Keep these aligned with provider docs:
// https://developers.openai.com/api/docs/pricing
// https://platform.claude.com/docs/en/build-with-claude/fast-mode
const openaiModels = new Set([
  "gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna",
  "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini",
  "gpt-5.2", "gpt-5.1", "gpt-5", "gpt-5-mini", "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano",
  "gpt-4o", "gpt-4o-mini", "o3", "o4-mini",
]);
const anthropicModels = new Set(["claude-opus-5-5", "claude-opus-5", "claude-opus-4-8"]);

export function supportsFastMode(model: Model<Api>): boolean {
  const id = model.id.replace(/-\d{4}-\d{2}-\d{2}$|-\d{8}$/, "");
  if (["openai", "openai-codex"].includes(model.provider) && ["openai-responses", "openai-codex-responses"].includes(model.api))
    return openaiModels.has(id);
  return model.provider === "anthropic" && model.api === "anthropic-messages" && anthropicModels.has(id);
}

export function fastModePayload(model: Model<Api>, payload: unknown, enabled: boolean): unknown {
  if (!supportsFastMode(model)) return payload;
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw new Error("Unexpected provider request payload");
  const request = payload as Record<string, unknown>;
  if (model.provider !== "anthropic") return { ...request, service_tier: enabled ? "priority" : "default" };
  // Opus 5.5 is generally available; the older preview models still require this beta.
  const preview = !model.id.startsWith("claude-opus-5-5");
  const betas = Array.isArray(request.betas) ? request.betas.filter(beta => beta !== "fast-mode-2026-02-01") : [];
  const { speed: _speed, ...standard } = request;
  return { ...standard, ...(preview && { betas: [...betas, ...(enabled ? ["fast-mode-2026-02-01"] : [])] }),
    ...(enabled && { speed: "fast" }) };
}
