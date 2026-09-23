import type { Store } from "../conversation/store.js";
import type { SessionCard } from "../conversation/types.js";

const LIST_CONVERSATIONS_TOOL = {
  name: "list_conversations",
  description: "List saved Agent conversations with titles and brief previews.",
  inputSchema: { type: "object", properties: {}, additionalProperties: false },
};

export const READ_CONVERSATION_TOOL = {
  name: "read_conversation",
  description: "Read recent saved messages without opening or resuming the conversation. Use nextBefore for older messages.",
  inputSchema: {
    type: "object",
    properties: { sessionId: { type: "string" }, before: { type: "integer" } },
    required: ["sessionId"],
    additionalProperties: false,
  },
};

const OPEN_CONVERSATION_TOOL = {
  name: "open_conversation",
  description: "Choose a listed conversation as the destination only after identifying a strong match.",
  inputSchema: {
    type: "object",
    properties: {
      sessionId: { type: "string" },
      task: { type: "string", description: "Work requested after resuming; omit for navigation only." },
    },
    required: ["sessionId"],
    additionalProperties: false,
  },
};

export const CONVERSATION_TOOLS = [LIST_CONVERSATIONS_TOOL, READ_CONVERSATION_TOOL, OPEN_CONVERSATION_TOOL];

export const READ_HISTORY_TOOL = {
  name: "read_history",
  description: "Read saved messages from the current conversation when the user asks to see earlier messages. Use nextBefore for older messages.",
  inputSchema: {
    type: "object",
    properties: { before: { type: "integer" } },
    additionalProperties: false,
  },
};

function response(success: boolean, text: string) {
  return { success, contentItems: [{ type: "inputText", text }] };
}

export function readHistory(store: Store, sessionId: string, argumentsValue: Record<string, unknown>) {
  const before = typeof argumentsValue.before === "number" && Number.isSafeInteger(argumentsValue.before) && argumentsValue.before > 0
    ? argumentsValue.before : undefined;
  return response(true, JSON.stringify(store.readConversation(sessionId, before)));
}

export function conversationTool(
  store: Store,
  cards: SessionCard[],
  name: string,
  argumentsValue: Record<string, unknown>,
): { result: ReturnType<typeof response>; navigateTo?: string } {
  if (name === "list_conversations") return { result: response(true, JSON.stringify(cards)) };

  const sessionId = typeof argumentsValue.sessionId === "string" ? argumentsValue.sessionId : "";
  if (name !== "read_conversation" && name !== "open_conversation") {
    return { result: response(false, "Unknown tool.") };
  }
  if (!cards.some((card) => card.id === sessionId)) {
    return { result: response(false, "Conversation not found.") };
  }
  if (name === "open_conversation") {
    return { result: response(true, `Opening agent://sessions/${sessionId}`), navigateTo: sessionId };
  }
  const before = typeof argumentsValue.before === "number" && Number.isSafeInteger(argumentsValue.before) && argumentsValue.before > 0
    ? argumentsValue.before : undefined;
  return { result: response(true, JSON.stringify(store.readConversation(sessionId, before))) };
}
