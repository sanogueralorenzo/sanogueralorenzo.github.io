import type { Socket } from "node:net";

export const stateDir: string;
export const socketPath: string;
export function getSourceId(): string;
export function connect(): Promise<Socket>;
export function ensureDaemon(): Promise<Socket>;
export function request(message: unknown): Promise<Record<string, unknown>>;
