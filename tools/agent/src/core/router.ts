import type { RouteDecision, TurnRequest } from "./types.js";

// Runtime modules stay small so clients can reconnect across fast reloads.

const CODE_HINTS = /\b(code|bug|fix|build|compile|test|repo|repository|file|function|class|api|git|commit|typescript|javascript|python|swift|kotlin|rust|java|sql|css|html|refactor|implement|debug)\b/i;
const DEEP_HINTS = /\b(architect|migrate|security|investigate|root cause|multi[- ]?step|redesign|performance|benchmark|review the (?:entire|whole))\b/i;
const QUICK_HINTS = /^(?:hi|hello|hey|thanks|thank you|what time|remind me|summari[sz]e this)\b/i;
const PERSONAL_HINTS = /\b(personal|remind me|what time|calendar|appointment|birthday|recipe|trip|travel|home|family|friend|habit|shopping)\b/i;

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
  const tier = DEEP_HINTS.test(text)
    ? "deep"
    : QUICK_HINTS.test(text) || text.length < 120
      ? "fast"
      : "standard";

  return {
    kind,
    tier,
    reasons: [
      explicitCode ? "coding language" : explicitPersonal ? "personal language" : projectContext ? "project context" : "personal context",
      tier === "deep" ? "complex task" : tier === "fast" ? "short task" : "general task",
    ],
    allowTools: kind === "coding",
    allowDelegation: tier === "deep",
  };
}
