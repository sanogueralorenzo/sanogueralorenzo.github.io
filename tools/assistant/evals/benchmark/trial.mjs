const clone = value => structuredClone(value);
export const matches = (actual, expected) => expected === null || typeof expected !== "object" ? actual === expected :
  Object.entries(expected).every(([key, value]) => actual != null && matches(actual[key], value));

function fixtureResult(call, test, variant, state) {
  if (!test.tools?.some(tool => tool.name === call.name)) return { error: true, text: "Tool is not available. No action was executed." };
  const rule = (test.fixtures || []).find(item => item.tool === call.name && matches(call.arguments, item.match || {}));
  if (!rule) return { error: true, text: "No fixture supports this action. No external action was executed." };
  if (rule.error) return { error: true, text: rule.response };
  if (rule.validateJSON) {
    const { stateKey, keys, types = {} } = rule.validateJSON;
    let valid = false;
    try {
      const value = JSON.parse(state[stateKey]);
      valid = value && !Array.isArray(value) && typeof value === "object" && Object.keys(value).sort().join() === keys.toSorted().join() && Object.entries(types).every(([key, type]) => typeof value[key] === type);
    } catch {}
    if (!valid) return { error: true, text: "Validation failed: saved artifact does not match the required JSON schema." };
  }
  for (const check of rule.validate || []) {
    const value = call.arguments[check.key];
    if (check.when && !matches(call.arguments, check.when)) continue;
    const valid = check.type === "nonempty" ? typeof value === "string" && Boolean(value.trim()) : check.type === "absent" ? value === undefined : check.type === "enum" ? check.values.includes(value) : false;
    if (!valid) return { error: true, text: `Invalid action: ${check.message}. Correct it and try again.` };
  }
  for (const [key, value] of Object.entries(rule.effects || {})) {
    state[key] = value && typeof value === "object" && "argument" in value ? clone(call.arguments[value.argument]) : clone(value);
  }
  return { error: Boolean(rule.error), text: rule.resource ? variant.resources[rule.resource] : rule.stateKey && state[rule.stateKey] !== undefined ? state[rule.stateKey] : rule.response, terminal: Boolean(rule.terminal) };
}

export async function runTrial(runtime, model, suite, job, options = {}) {
  const { test, variant, repeat, id } = job;
  const started = performance.now();
  const signal = AbortSignal.timeout(options.timeoutMs || 60000);
  const state = clone(test.initialState || {});
  const messages = suite.config.mode === "suggestion" ? [{ role: "user", timestamp: 0, content: JSON.stringify({ conversation: test.messages
    .filter(m => ["user", "assistant"].includes(m.role)).slice(-12).map(({ role, text }) => ({ role, text: text.slice(-6000) })) }) }] :
    test.messages.map(({ role, text }) => ({ role, timestamp: 0, content: [{ type: "text", text }] }));
  const record = { id, caseId: test.id, family: test.family, category: test.category, variant: variant.id, repeat, trace: [], state, usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0 }, requests: [], text: "" };
  try {
    for (let turn = 0; turn < (suite.config.maxTurns || 6); turn++) {
      let request; let response;
      const stream = runtime.streamSimple(model, { systemPrompt: variant.prompt, messages, ...(test.tools?.length && { tools: test.tools }) }, {
        reasoning: variant.effort, transport: "sse", maxRetries: 0, signal,
        onPayload: payload => {
          const value = { ...payload, service_tier: "priority" };
          request = { model: value.model, effort: value.reasoning?.effort, tier: value.service_tier };
          if (request.effort !== (variant.effort === "off" ? "none" : variant.effort)) throw new Error("Provider effort differs from requested effort");
          return value;
        },
        onProviderStreamEvent: event => {
          if (event.type === "response.completed") response = { model: event.response?.model, tier: event.response?.service_tier, reasoningTokens: event.response?.usage?.output_tokens_details?.reasoning_tokens };
        },
      });
      for await (const event of stream) if (event.type === "text_delta" && event.delta && record.firstTextMs === undefined) record.firstTextMs = performance.now() - started;
      const answer = await stream.result();
      record.requests.push({ request, response, usage: answer.usage });
      for (const key of Object.keys(record.usage)) record.usage[key] += answer.usage?.[key] || 0;
      const text = answer.content.filter(p => p.type === "text").map(p => p.text).join("").trim();
      const calls = answer.content.filter(p => p.type === "toolCall");
      record.trace.push({ role: "assistant", text, calls });
      if (["error", "aborted"].includes(answer.stopReason)) throw new Error(answer.errorMessage || answer.stopReason);
      if (!calls.length) { record.text = text; record.completed = answer.stopReason === "stop"; break; }
      messages.push(answer);
      let terminal = false;
      for (const call of calls) {
        const result = fixtureResult(call, test, variant, state);
        if (typeof result.text !== "string") throw new Error("Fixture response or resource is missing");
        record.trace.push({ role: "tool", name: call.name, arguments: call.arguments, text: result.text, error: result.error });
        messages.push({ role: "toolResult", toolCallId: call.id, toolName: call.name, content: [{ type: "text", text: result.text }], isError: result.error, timestamp: 0 });
        if (result.terminal) { terminal = true; break; }
      }
      if (terminal) { record.completed = true; break; }
    }
    if (!record.completed) record.agentFailure = "Turn limit exceeded or model did not finish";
  } catch (error) { record.error = error.message; }
  record.elapsedMs = performance.now() - started;
  record.deadlineExceeded = record.elapsedMs > (suite.config.deadlineMs || 60000);
  return record;
}
