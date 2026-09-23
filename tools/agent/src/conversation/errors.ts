export function failureMessage(error: unknown, signal?: AbortSignal): string {
  if (signal?.aborted || (error instanceof Error && error.name === "AbortError")) {
    return "Interrupted. Your session is saved.";
  }
  const message = error instanceof Error ? error.message : String(error);
  return message.toLowerCase().includes("already has an active writer")
    ? "This linked Codex task is still owned by an active writer in Codex or another session. Agent won’t duplicate or resend your request. Try again after that owner releases the linked task."
    : message;
}
