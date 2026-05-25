import { describe, expect, it, vi } from "vitest";
import { BindingStore } from "../adapters/binding-store.js";
import { createThreadActions, ListedFolderChoice, ListedThread } from "./thread-actions.js";

function makeThreadActionsState() {
  const selectionStateByChat = new Map<
    string,
    { sessions: ListedThread[]; mode: "resume" | "delete"; folderChoices: ListedFolderChoice[] }
  >();
  const bindChatToThread = vi.fn(async () => {});
  const store = {
    get: vi.fn(async () => null),
    remove: vi.fn(async () => {}),
    set: vi.fn(async () => {}),
  };

  const actions = createThreadActions({
    codexHome: "/tmp/codex-home",
    defaultThreadsLimit: 25,
    store: store as unknown as BindingStore,
    pendingNewSessionChats: new Set<string>(),
    pendingNewSessionCwds: new Map<string, string>(),
    selectionStateByChat,
    resolveDefaultCwd: () => "/tmp/default",
    bindChatToThread,
  });

  return {
    actions,
    bindChatToThread,
    selectionStateByChat,
  };
}

describe("createThreadActions", () => {
  it("keeps invalid pending thread selections out of the active Codex prompt", async () => {
    const { actions, bindChatToThread, selectionStateByChat } = makeThreadActionsState();
    const reply = vi.fn(async () => {});
    selectionStateByChat.set("chat-1", {
      sessions: [
        { id: "thread-1", title: "Fix billing flow", cwd: "/tmp/project" },
      ],
      mode: "resume",
      folderChoices: [],
    });

    const handled = await actions.tryPickThreadByText("chat-1", "this is a normal prompt", reply);

    expect(handled).toBe(true);
    expect(bindChatToThread).not.toHaveBeenCalled();
    expect(reply).toHaveBeenCalledWith(
      "Choose a thread to resume by number.",
      expect.objectContaining({ reply_markup: expect.anything() })
    );
  });

  it("keeps invalid pending folder selections out of the active Codex prompt", async () => {
    const { actions, selectionStateByChat } = makeThreadActionsState();
    const reply = vi.fn(async () => {});
    selectionStateByChat.set("chat-1", {
      sessions: [],
      mode: "resume",
      folderChoices: [
        { cwd: "/tmp/project", label: "project" },
      ],
    });

    const handled = await actions.tryPickFolderChoiceByText("chat-1", "this is a normal prompt", reply);

    expect(handled).toBe(true);
    expect(reply).toHaveBeenCalledWith(
      "Choose a folder by number.",
      expect.objectContaining({ reply_markup: expect.anything() })
    );
  });
});
