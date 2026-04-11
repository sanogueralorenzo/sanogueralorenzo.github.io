import { asObject, getString, normalizeTextToken } from "./json.js";

export function normalizeItemType(type: string | null): string {
  if (!type) {
    return "unknown";
  }

  const token = normalizeTextToken(type);
  switch (token) {
    case "agentmessage":
      return "agentMessage";
    case "usermessage":
      return "userMessage";
    case "reasoning":
      return "reasoning";
    case "plan":
      return "plan";
    case "commandexecution":
      return "commandExecution";
    case "filechange":
      return "fileChange";
    case "toolcall":
      return "toolCall";
    case "toolresult":
      return "toolResult";
    case "collabtoolcall":
      return "collabToolCall";
    default:
      return type;
  }
}

export function isCommandOutputDeltaMethod(method: string): boolean {
  return (
    method === "item/fileChange/outputDelta" ||
    method === "item/commandExecution/outputDelta" ||
    method === "command/exec/outputDelta"
  );
}

export function extractDeltaItemType(method: string): string {
  if (method === "item/fileChange/outputDelta") {
    return "fileChange";
  }
  if (method === "item/commandExecution/outputDelta" || method === "command/exec/outputDelta") {
    return "commandExecution";
  }
  return "unknown";
}

export function extractDeltaText(params: Record<string, unknown>): string | null {
  return (
    getString(params.delta) ??
    getString(params.textDelta) ??
    getString(params.summaryTextDelta) ??
    getString(params.outputDelta) ??
    getString(params.text)
  );
}

export function extractItemStatus(item: Record<string, unknown>): string | null {
  const statusValue = item.status;
  if (typeof statusValue === "string") {
    return statusValue;
  }
  return getString(asObject(statusValue).type);
}

export function extractCommandText(item: Record<string, unknown>): string | null {
  return getString(item.command);
}

export function extractItemOutput(item: Record<string, unknown>): string | null {
  return getString(item.aggregatedOutput) ?? getString(item.aggregated_output) ?? getString(item.output);
}

export function extractItemText(item: Record<string, unknown>): string | null {
  return getString(item.text) ?? getString(item.summary);
}
