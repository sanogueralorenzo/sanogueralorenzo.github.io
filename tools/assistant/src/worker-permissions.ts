import { defineDoc, type Agent, type ToolRegistration } from "@earendil-works/pi-durable";
import { Type } from "typebox";

const readTools = ["read", "grep", "find", "ls"];
const permissions = {
  "files.write": { access: ["edit", "write"], tools: ["edit", "write"] },
  "commands.run": { access: ["bash"], tools: ["bash", "edit", "write"] },
} as const;
export type WorkerPermission = keyof typeof permissions;
export const workerPermissionsSchema = Type.Array(Type.Union((Object.keys(permissions) as WorkerPermission[]).map(permission => Type.Literal(permission))), { uniqueItems: true });
type WorkerPermissions = { permissions: WorkerPermission[]; tools: string[] };

export const WorkerPermissionsDoc = defineDoc<WorkerPermissions>({ kind: "assistant.worker-permissions", version: 2,
  scope: "conversation", history: "latest", fork: "initial", initial: () => ({ permissions: [], tools: [] }) });

export function resolveWorkerPermissions(requested: WorkerPermission[], parent: Agent, parentTools: readonly string[]): WorkerPermissions {
  const workerParent = parent.extensions.some(extension => extension.name === "assistant-worker");
  const available = parent.tools.map(tool => tool.name).filter(name => !workerParent || parentTools.includes(name));
  for (const permission of requested) {
    if (!permissions[permission].access.some(name => available.includes(name)))
      throw new Error(`Parent cannot grant ${permission}`);
  }
  const allowed = new Set([...readTools, ...requested.flatMap(permission => permissions[permission].tools)]);
  return { permissions: [...requested], tools: available.filter(name => allowed.has(name)) };
}

export function workerTools(tools: readonly ToolRegistration[], names: readonly string[]) {
  return tools.filter(tool => names.includes(tool.name));
}

export function requireWorkerTool(name: string, tools: readonly string[]) {
  if (!tools.includes(name)) throw new Error(`Worker permission denied for ${name}`);
}
