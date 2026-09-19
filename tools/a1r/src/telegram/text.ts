export function splitTelegramText(text: string, limit = 4096): string[] {
  const chunks: string[] = [];
  let remaining = text.trim();
  while (remaining.length > limit) {
    const candidate = remaining.slice(0, limit + 1);
    const paragraph = candidate.lastIndexOf("\n\n");
    const line = candidate.lastIndexOf("\n");
    const space = candidate.lastIndexOf(" ");
    const splitAt = Math.max(paragraph, line, space, Math.min(limit, candidate.length));
    chunks.push(remaining.slice(0, splitAt).trimEnd());
    remaining = remaining.slice(splitAt).trimStart();
  }
  if (remaining) chunks.push(remaining);
  return chunks;
}

export function pairingHash(code: string): string {
  return createHash("sha256").update(code).digest("hex");
}
import { createHash } from "node:crypto";
