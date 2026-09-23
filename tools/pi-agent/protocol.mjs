import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createConnection } from "node:net";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const stateDir = process.env.PI_AGENT_STATE_DIR || join(homedir(), ".pi", "agent-delegation");
export const socketPath = join(stateDir, "daemon.sock");
const sourcePath = join(stateDir, "source.id");
const daemonPath = join(dirname(fileURLToPath(import.meta.url)), "daemon.mjs");

export function getSourceId() {
  mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  try { writeFileSync(sourcePath, randomUUID(), { flag: "wx", mode: 0o600 }); }
  catch (error) { if (error?.code !== "EEXIST") throw error; }
  return readFileSync(sourcePath, "utf8").trim();
}

export async function connect() {
  return await new Promise((resolve, reject) => {
    const socket = createConnection(socketPath);
    socket.once("connect", () => resolve(socket));
    socket.once("error", reject);
  });
}

export async function ensureDaemon() {
  try { return await connect(); } catch (error) {
    if (!["ENOENT", "ECONNREFUSED"].includes(error?.code)) throw error;
  }
  mkdirSync(stateDir, { recursive: true, mode: 0o700 });
  const child = spawn(process.execPath, [daemonPath], { detached: true, stdio: "ignore" });
  child.unref();
  for (let attempt = 0; attempt < 30; attempt++) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    try { return await connect(); } catch (error) {
      if (!["ENOENT", "ECONNREFUSED"].includes(error?.code)) throw error;
    }
  }
  throw new Error("Pi Agent daemon did not start");
}

export async function request(message) {
  const socket = await ensureDaemon();
  return await new Promise((resolve, reject) => {
    let buffer = "";
    socket.on("data", (chunk) => {
      buffer += chunk.toString();
      const newline = buffer.indexOf("\n");
      if (newline < 0) return;
      try {
        const result = JSON.parse(buffer.slice(0, newline));
        if (result.ok) resolve(result);
        else reject(new Error(result.error || "Daemon request failed"));
      } catch (error) { reject(error); }
      socket.end();
    });
    socket.once("error", reject);
    socket.once("close", () => { if (!buffer.includes("\n")) reject(new Error("Daemon disconnected")); });
    socket.write(`${JSON.stringify(message)}\n`);
  });
}
