import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Target } from "./conversation.ts";

export type Draft = {
  text: string;
  reply?: Target;
  edit?: { target: Target; previous: Draft };
  queuedEdit?: { sessionId: string; text: string; previous: Draft };
};

export function savedDrafts(url: URL, onError: (message: string) => void) {
  const directory = join(homedir(), ".agent");
  const host = createHash("sha256").update(url.origin).digest("hex").slice(0, 16);
  const path = join(directory, `terminal-${host}.json`);
  let saved: { view: string; drafts: Record<string, Draft> } = { view: "home", drafts: {} };
  try {
    const stored = JSON.parse(readFileSync(path, "utf8"));
    if (typeof stored?.view === "string" && stored.drafts && typeof stored.drafts === "object") saved = stored;
  } catch {}
  const drafts = new Map(Object.entries(saved.drafts));
  let timer: ReturnType<typeof setTimeout> | undefined;
  let view = saved.view;

  function flush() {
    if (!timer) return;
    clearTimeout(timer);
    timer = undefined;
    try {
      mkdirSync(directory, { recursive: true });
      const temp = `${path}.${process.pid}.tmp`;
      writeFileSync(temp, JSON.stringify({ view, drafts: Object.fromEntries(drafts) }), { mode: 0o600 });
      renameSync(temp, path);
    } catch (error) {
      onError(`Could not save drafts: ${(error as Error).message}`);
    }
  }

  function persist() {
    clearTimeout(timer);
    timer = setTimeout(flush, 150);
    timer.unref();
  }

  return {
    get view() { return view; },
    get(id: string): Draft { return drafts.get(id) ?? { text: "" }; },
    set(id: string, draft: Draft) {
      if (draft.text || draft.reply || draft.edit || draft.queuedEdit) drafts.set(id, draft);
      else drafts.delete(id);
      persist();
    },
    select(id: string) { view = id; persist(); },
    flush,
  };
}
