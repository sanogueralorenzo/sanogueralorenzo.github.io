import type { RouteDecision, TurnRequest } from "./types.js";

// Runtime modules stay small so clients can reconnect across fast reloads.

const CODE_HINTS = /\b(code|bug|fix|build|compile|test|repo|repository|file|function|class|api|git|commit|typescript|javascript|python|swift|kotlin|rust|java|sql|css|html|refactor|implement|debug)\b/i;
const QUICK_HINTS = /^(?:hi|hello|hey|thanks|thank you|what time|remind me|summari[sz]e this)\b/i;
const PERSONAL_HINTS = /\b(personal|remind me|what time|calendar|appointment|birthday|recipe|trip|travel|home|family|friend|habit|shopping)\b/i;
const CASUAL_ONLY = /^(?:hi|hello|hey|thanks|thank you|good (?:morning|afternoon|evening))[!. ]*$/i;
const COORDINATOR_ONLY = /^(?:please\s+)?remember(?:\s+that)?\b/i;
const ASTRA_REQUEST = /\b(?:use|spawn|delegate(?:\s+to)?|ask|run|invoke|hand\s*off(?:\s+to)?)\s+(?:an?\s+)?(?:gpt[- ]?6[- ]?)?astra(?:\s+(?:high|agent|worker|subagent))?\b/i;
const ASTRA_NEGATION = /\b(?:do not|don't|never|without|avoid)\s+(?:use|spawning?|delegat(?:e|ing)(?:\s+to)?|ask(?:ing)?|run(?:ning)?|invok(?:e|ing))\s+(?:an?\s+)?(?:gpt[- ]?6[- ]?)?astra\b/i;

export function explicitlyRequestsAstra(text: string): boolean {
  return ASTRA_REQUEST.test(text) && !ASTRA_NEGATION.test(text);
}

export function routeTurn(request: TurnRequest, priorKind?: "personal" | "coding"): RouteDecision {
  const text = request.text.trim();
  const projectContext = Boolean(request.cwd && request.channel !== "telegram");
  const explicitCode = CODE_HINTS.test(text);
  const explicitPersonal = PERSONAL_HINTS.test(text);
  const kind = explicitCode
    ? "coding"
    : explicitPersonal
      ? "personal"
      : priorKind ?? (projectContext && !QUICK_HINTS.test(text) ? "coding" : "personal");
  const worker = explicitlyRequestsAstra(text)
    ? "astra"
    : kind === "coding"
      ? "coding"
      : !CASUAL_ONLY.test(text) && !COORDINATOR_ONLY.test(text) && (QUICK_HINTS.test(text) || text.length < 240)
        ? "bounded"
        : null;

  return {
    kind,
    worker,
    reasons: [
      explicitCode ? "coding language" : explicitPersonal ? "personal language" : projectContext ? "project context" : "personal context",
      worker === "astra" ? "explicit Astra request" : worker === "coding" ? "coding implementation" : worker === "bounded" ? "bounded task" : "coordinator task",
    ],
  };
}
