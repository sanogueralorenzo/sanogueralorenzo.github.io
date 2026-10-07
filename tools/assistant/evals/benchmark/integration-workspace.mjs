import { readFileSync, readdirSync } from "node:fs";
import { join, resolve, relative, isAbsolute } from "node:path";
import { assistantText } from "../../src/state.ts";
import { hash } from "./suite.mjs";

export function workspacePath(root, path = ".") {
  // Native Pi tools strip @ and expand ~ before resolving a path.
  path = path.replace(/^@/, "").replace(/[\u00a0\u2000-\u200a\u202f\u205f\u3000]/g, " ");
  if (path.startsWith("~")) throw new Error("Path is outside the benchmark workspace");
  const full = resolve(root, path);
  const rel = relative(root, full);
  if (rel === ".." || rel.startsWith("../") || isAbsolute(rel)) throw new Error("Path is outside the benchmark workspace");
  return full;
}

export function workspaceSnapshot(root) {
  const files = {};
  const visit = dir => {
    for (const item of readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const path = join(dir, item.name);
      if (item.isSymbolicLink()) throw new Error("Benchmark workspaces must not contain symlinks");
      if (item.isDirectory()) visit(path);
      else files[relative(root, path)] = hash(readFileSync(path));
    }
  };
  visit(root);
  return files;
}

export function recordAssistantMessage(record, message, normalize = text => text) {
  for (const key of Object.keys(record.usage)) record.usage[key] += message.usage?.[key] || 0;
  if (record.requests?.length) record.requests.at(-1).usage = message.usage;
  const text = message.content.filter(p => p.type === "text").map(p => p.text).join("\n");
  record.trace.push({ role: "assistant", text: normalize(text), calls: message.content.filter(p => p.type === "toolCall"), stopReason: message.stopReason });
  record.text = normalize(assistantText(message));
  record.completed = message.stopReason === "stop";
  if (message.stopReason === "error") {
    record.error = message.errorMessage || "Provider failed";
    record.providerErrors = [...(record.providerErrors || []), record.error];
  } else delete record.error;
}
