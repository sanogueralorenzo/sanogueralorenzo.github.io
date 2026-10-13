import { defineDoc, type Agent, type ToolRegistration } from "@earendil-works/pi-durable";
import { Type, type Static } from "typebox";

const Permission = Type.Union([Type.Literal("files.read"), Type.Literal("files.write"), Type.Literal("commands.run"), Type.Literal("web.search")]);
export type WorkerPermission = Static<typeof Permission>;
export const workerPermissionsSchema = Type.Array(Permission, { uniqueItems: true });
const permissionTools: Record<WorkerPermission, readonly string[]> = {
  "files.read": ["read", "grep", "find", "ls"],
  "files.write": ["edit", "write"],
  "commands.run": ["bash"],
  "web.search": [],
};

export const WorkerPermissionsDoc = defineDoc<{ permissions: WorkerPermission[] }>({ kind: "assistant.worker-permissions", version: 1,
  scope: "conversation", history: "latest", fork: "initial", initial: () => ({ permissions: [] }) });

export function canSearch(agent: Agent, permissions: readonly WorkerPermission[]) {
  return agent.extensions.some(extension => extension.name === "assistant-worker") ? permissions.includes("web.search")
    : agent.extensions.some(extension => extension.name === "assistant-session");
}

export function validateWorkerPermissions(permissions: WorkerPermission[], parent: Agent, parentPermissions: readonly WorkerPermission[]) {
  if (permissions.includes("files.write") && !permissions.includes("files.read")) throw new Error("files.write requires files.read");
  if (permissions.includes("commands.run") && (!permissions.includes("files.read") || !permissions.includes("files.write")))
    throw new Error("commands.run requires files.read and files.write because shell commands can read and modify files");
  for (const permission of permissions) {
    if (permission === "web.search" ? !canSearch(parent, parentPermissions)
      : permissionTools[permission].some(name => !parent.tools.some(tool => tool.name === name)))
      throw new Error(`Parent cannot grant ${permission}`);
    if (parent.extensions.some(extension => extension.name === "assistant-worker") && !parentPermissions.includes(permission))
      throw new Error(`Parent cannot grant ${permission}`);
  }
}

export function workerTools(tools: readonly ToolRegistration[], permissions: readonly WorkerPermission[]) {
  return tools.filter(tool => permissions.some(permission => permissionTools[permission].includes(tool.name)));
}

export function requireWorkerTool(name: string, permissions: readonly WorkerPermission[]) {
  if (!permissions.some(permission => permissionTools[permission].includes(name))) throw new Error(`Worker permission denied for ${name}`);
}
