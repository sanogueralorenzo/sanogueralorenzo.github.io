import { randomUUID } from "node:crypto";
import { chmodSync, copyFileSync, mkdirSync, statSync, writeFileSync } from "node:fs";
import { basename, extname, join } from "node:path";
import type { Store } from "../conversation/store.js";
import type { Artifact, Attachment } from "../conversation/types.js";

export const MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024;

function safeName(value: string): string {
  const name = basename(value).replaceAll(/[^a-zA-Z0-9._ -]/g, "_").slice(0, 120).trim();
  return name && name !== "." && name !== ".." ? name : "attachment";
}

function extensionFor(mimeType: string): string {
  const known: Record<string, string> = {
    "audio/ogg": ".ogg",
    "audio/mpeg": ".mp3",
    "audio/mp4": ".m4a",
    "audio/wav": ".wav",
    "audio/webm": ".webm",
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "application/pdf": ".pdf",
  };
  return known[mimeType] ?? "";
}

function destination(homeDir: string, directoryName: "attachments" | "artifacts", extension: string) {
  const id = randomUUID();
  const directory = join(homeDir, directoryName);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  chmodSync(directory, 0o700);
  return { id, path: join(directory, `${id}${extension}`) };
}

function artifact(file: Omit<Artifact, "kind">): Artifact {
  return { ...file, kind: file.mimeType.startsWith("image/") ? "image" : "file" };
}

function saveData(homeDir: string, directory: "attachments" | "artifacts", input: { name: string; mimeType: string; data: Buffer }) {
  const name = safeName(input.name);
  const { id, path } = destination(homeDir, directory, extname(name) || extensionFor(input.mimeType));
  writeFileSync(path, input.data, { mode: 0o600, flag: "wx" });
  return { id, path, name, mimeType: input.mimeType, size: input.data.length };
}

export function saveAttachment(
  homeDir: string,
  store: Store,
  input: { name: string; mimeType: string; data: Buffer },
): Attachment {
  if (input.data.length === 0) throw new Error("Attachment is empty.");
  if (input.data.length > MAX_ATTACHMENT_BYTES) throw new Error("Attachment exceeds the 25 MB limit.");
  if (!input.mimeType.startsWith("audio/")) throw new Error("Only voice-note attachments are supported.");
  return store.addAttachment(saveData(homeDir, "attachments", input));
}

export function saveArtifactData(
  homeDir: string,
  input: { name: string; mimeType: string; data: Buffer },
): Artifact {
  if (input.data.length === 0) throw new Error("Artifact is empty.");
  return artifact(saveData(homeDir, "artifacts", input));
}

export function saveArtifactPath(
  homeDir: string,
  input: { path: string; name?: string; mimeType?: string },
): Artifact {
  const source = input.path;
  const sourceStat = statSync(source);
  if (!sourceStat.isFile()) throw new Error("Artifact path is not a file.");
  const name = safeName(input.name ?? basename(source));
  const extension = extname(name) || extname(source);
  const mimeType = input.mimeType ?? mimeForExtension(extension);
  const { id, path } = destination(homeDir, "artifacts", extension);
  copyFileSync(source, path);
  chmodSync(path, 0o600);
  return artifact({ id, path, name, mimeType, size: sourceStat.size });
}

function mimeForExtension(extension: string): string {
  const known: Record<string, string> = {
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp",
    ".gif": "image/gif", ".pdf": "application/pdf", ".txt": "text/plain", ".md": "text/markdown",
    ".json": "application/json", ".zip": "application/zip",
  };
  return known[extension.toLowerCase()] ?? "application/octet-stream";
}
