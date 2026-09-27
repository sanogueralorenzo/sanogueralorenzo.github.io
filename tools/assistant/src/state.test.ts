import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { State, now, type Turn } from "./state.ts";

test("saving a changed record leaves unrelated SQLite rows untouched", () => {
  const dir = mkdtempSync(join(tmpdir(), "assistant-state-"));
  const state = new State(dir, () => {});
  try {
    const message = state.message("first", "message-1");
    const entry = state.entry(message, "First", null, "entry-1");
    state.db.exec("CREATE TABLE audit (table_name TEXT, action TEXT)");
    for (const table of ["messages", "entries", "sessions", "turns"]) {
      for (const action of ["INSERT", "UPDATE", "DELETE"]) {
        state.db.exec(`CREATE TRIGGER audit_${table}_${action} AFTER ${action} ON ${table}
          BEGIN INSERT INTO audit VALUES ('${table}', '${action}'); END`);
      }
    }
    const changes = () => state.db.prepare("SELECT table_name, action FROM audit ORDER BY rowid").all()
      .map((row) => ({ table_name: row.table_name, action: row.action }));
    state.save();
    assert.deepEqual(changes(), []);

    entry.title = "Revised";
    state.save();
    assert.deepEqual(changes(), [{ table_name: "entries", action: "UPDATE" }]);

    state.db.exec("DELETE FROM audit");
    state.message("second", "message-2");
    assert.deepEqual(changes(), [{ table_name: "messages", action: "INSERT" }]);
  } finally {
    state.db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a resumed turn keeps its place ahead of queued turns after restart", () => {
  const dir = mkdtempSync(join(tmpdir(), "assistant-state-"));
  const state = new State(dir, () => {});
  let reopened: State | undefined;
  try {
    const message = state.message("request");
    const entry = state.entry(message, "Request", "session-1");
    state.data.sessions.push({ id: "session-1", title: "Request", cwd: dir, file: join(dir, "session.jsonl"), status: "idle", createdAt: now() });
    const turn = (id: string): Turn => ({ id, sessionId: "session-1", entryId: entry.id, text: id, status: "queued", createdAt: now() });
    state.data.turns.push(turn("waiting-1"), turn("waiting-2"));
    state.save();
    state.data.turns.unshift(turn("resumed"));
    state.save();
    state.db.close();

    reopened = new State(dir, () => {});
    assert.deepEqual(reopened.data.turns.map((item) => item.id), ["resumed", "waiting-1", "waiting-2"]);
  } finally {
    if (state.db.isOpen) state.db.close();
    reopened?.db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
