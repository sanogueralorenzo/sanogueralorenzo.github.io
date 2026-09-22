export function failureMessage(error: unknown, signal?: AbortSignal): string {
  return signal?.aborted || (error instanceof Error && error.name === "AbortError")
    ? "Interrupted. Your session is saved."
    : error instanceof Error ? error.message : String(error);
}
