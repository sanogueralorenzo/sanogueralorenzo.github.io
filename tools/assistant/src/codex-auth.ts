import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

type CodexTokens = { access_token: string; refresh_token: string; account_id: string };
type PiCredential = { type: "oauth"; access: string; refresh: string; expires: number; accountId: string };

// Keep Assistant's renewable credential separate from Pi's saved login. The
// Codex CLI account is the account the user selected for this local service.
export function assistantCodexAuth(dataDir: string): string {
  const source = join(homedir(), ".codex", "auth.json");
  if (!existsSync(source)) throw new Error("Codex is not signed in; sign in with the Codex CLI first");
  const tokens = (JSON.parse(readFileSync(source, "utf8")) as { tokens?: CodexTokens }).tokens;
  if (!tokens?.access_token || !tokens.refresh_token || !tokens.account_id) throw new Error("Codex login has no usable ChatGPT credentials");
  const path = join(dataDir, "codex-auth.json");
  const previous = existsSync(path) ? (JSON.parse(readFileSync(path, "utf8")) as { "openai-codex"?: PiCredential })["openai-codex"] : undefined;
  const accessExpiry = Number(JSON.parse(Buffer.from(tokens.access_token.split(".")[1], "base64url").toString())?.exp) * 1000;
  if (!Number.isFinite(accessExpiry)) throw new Error("Codex access token has no expiry");
  if (previous?.accountId === tokens.account_id && previous.expires >= accessExpiry) return path;
  mkdirSync(dataDir, { recursive: true, mode: 0o700 });
  const credential: PiCredential = { type: "oauth", access: tokens.access_token, refresh: tokens.refresh_token, expires: accessExpiry, accountId: tokens.account_id };
  writeFileSync(path, JSON.stringify({ "openai-codex": credential }), { mode: 0o600 });
  return path;
}
