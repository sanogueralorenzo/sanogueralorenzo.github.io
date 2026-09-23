import { describe, expect, it } from "vitest";
import { Store } from "../conversation/store.js";
import { temporary } from "../test-support.js";

describe("Home persistence", () => {
  it("keeps activity chronological and gives status only to a session's latest entry", () => {
    const store = new Store(temporary("agent-home-store-"));
    const first = store.createSession({ title: "First" });
    const second = store.createSession({ title: "Second" });
    store.home.createEntry("first", "original first");
    store.home.dispatchEntry("first", first.id, first.title, "clear first", true);
    store.home.createEntry("second", "original second");
    store.home.dispatchEntry("second", second.id, second.title, "clear second", false);
    store.home.createEntry("earlier-follow-up", "earlier follow up");
    store.home.dispatchEntry("earlier-follow-up", first.id, first.title, "earlier follow up", false);
    store.db.prepare("UPDATE home_entries SET state = 'ready' WHERE id = 'first'").run();
    store.home.createEntry("follow-up", "follow up");
    const dispatched = store.home.dispatchEntry("follow-up", first.id, first.title, "clear follow up", true);
    const after = store.home.updateEntry(first.id, "needs_input", "Which branch should I use?")!;
    expect(dispatched.superseded.map((entry) => entry.id)).toEqual(["earlier-follow-up", "first"]);
    expect(store.home.entries().map((entry) => entry.id)).toEqual(["first", "second", "earlier-follow-up", "follow-up"]);
    expect(store.home.entries().map((entry) => entry.state)).toEqual([null, "ready", null, "needs_input"]);
    expect(after).toMatchObject({ summary: "Which branch should I use?", url: `agent://sessions/${first.id}` });
    store.close();
  });

  it("retains queued follow-ups through restart and consumes them with their run", () => {
    const path = temporary("agent-queued-");
    const store = new Store(path);
    const session = store.createSession({ title: "Saved work" });
    store.home.createEntry("queued", "First follow-up");
    store.home.dispatchEntry("queued", session.id, session.title, "First follow-up", true);
    store.home.enqueueTask(session.id, "First follow-up", "macos");
    store.home.enqueueTask(session.id, "Second follow-up", "telegram");
    store.close();

    const recovered = new Store(path);
    expect(recovered.home.entries()[0]).toMatchObject({ state: "working", summary: null });
    expect(recovered.home.queuedSessionIds()).toEqual([session.id]);
    const first = recovered.home.queuedTask(session.id)!;
    recovered.startRun(session.id, "queued-run", first.text, first.id);
    expect(recovered.home.queuedTask(session.id)?.text).toBe("Second follow-up");
    recovered.finishRun("queued-run", "complete", "Done.");
    recovered.close();
  });
});
