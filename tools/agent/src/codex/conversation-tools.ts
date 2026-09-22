import type { Store } from "../conversation/store.js";
import type { SessionCard } from "../conversation/types.js";

export const CONVERSATION_TOOLS = [
  {
    name: "list_conversations",
    description: "List saved Agent conversations with titles and brief previews.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "read_conversation",
    description: "Read recent messages from a listed conversation when its preview is not enough to identify it. Use nextBefore for older messages.",
    inputSchema: {
      type: "object",
      properties: { sessionId: { type: "string" }, before: { type: "integer" } },
      required: ["sessionId"],
      additionalProperties: false,
    },
  },
  {
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
  },
];

function response(success: boolean, text: string) {
  return { success, contentItems: [{ type: "inputText", text }] };
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
