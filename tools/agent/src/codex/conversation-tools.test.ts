import { describe, expect, it } from "vitest";
import { Store } from "../conversation/store.js";
import { cleanup, temporary } from "../test-support.js";
import { conversationTool } from "./conversation-tools.js";

describe("conversation tools", () => {
  it("cannot read or open a conversation that was not offered to the turn", () => {
    const store = new Store(temporary("agent-conversation-tools-"));
    cleanup(() => store.close());
    const saved = store.createSession();
    store.addMessage(saved.id, "user", "private details");

    for (const name of ["read_conversation", "open_conversation"]) {
      const answer = conversationTool(store, [], name, { sessionId: saved.id });
      expect(answer.result).toMatchObject({ success: false, contentItems: [{ text: "Conversation not found." }] });
      expect(answer.navigateTo).toBeUndefined();
    }
  });
});
