import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

export function ensurePrivateDirectory(path: string): void {
  mkdirSync(path, { recursive: true, mode: 0o700 });
  const stat = lstatSync(path);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`${path} must be a real directory.`);
  if (typeof process.getuid === "function" && stat.uid !== process.getuid()) throw new Error(`${path} is owned by another user.`);
  chmodSync(path, 0o700);
}

export function readPrivateJson<T>(path: string): T | null {
  try {
    if (lstatSync(path).isSymbolicLink()) return null;
    return JSON.parse(readFileSync(path, "utf8")) as T;
  } catch {
    return null;
  }
}

export function writePrivateFile(path: string, content: string, mode = 0o600): void {
  ensurePrivateDirectory(dirname(path));
  if (existsSync(path) && lstatSync(path).isSymbolicLink()) throw new Error(`${path} must not be a symbolic link.`);
  const temporary = `${path}.${process.pid}.tmp`;
  writeFileSync(temporary, content, { mode });
  renameSync(temporary, path);
  chmodSync(path, mode);
}

export function writePrivateJson(path: string, value: unknown): void {
  writePrivateFile(path, `${JSON.stringify(value, null, 2)}\n`);
}
