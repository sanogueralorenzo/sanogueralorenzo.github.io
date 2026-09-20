import { randomUUID } from "node:crypto";
import { chmodSync, copyFileSync, mkdirSync, statSync, writeFileSync } from "node:fs";
import { basename, extname, join } from "node:path";
import type { Store } from "./store.js";
import type { Artifact, Attachment, AttachmentKind } from "./types.js";

export const MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024;

function safeName(value: string): string {
  const name = basename(value).replaceAll(/[^a-zA-Z0-9._ -]/g, "_").slice(0, 120).trim();
  return name && name !== "." && name !== ".." ? name : "attachment";
}

function kindFor(mimeType: string): AttachmentKind {
  if (mimeType.startsWith("audio/")) return "audio";
  if (mimeType.startsWith("image/")) return "image";
  return "file";
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

export function saveAttachment(
  homeDir: string,
  store: Store,
  input: { name: string; mimeType: string; data: Buffer },
): Attachment {
  if (input.data.length === 0) throw new Error("Attachment is empty.");
  if (input.data.length > MAX_ATTACHMENT_BYTES) throw new Error("Attachment exceeds the 25 MB limit.");
  const id = randomUUID();
  const name = safeName(input.name);
  const extension = extname(name) || extensionFor(input.mimeType);
  const directory = join(homeDir, "attachments");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  chmodSync(directory, 0o700);
  const path = join(directory, `${id}${extension}`);
  writeFileSync(path, input.data, { mode: 0o600, flag: "wx" });
  return store.addAttachment({
    id,
    kind: kindFor(input.mimeType),
    name,
    mimeType: input.mimeType,
    size: input.data.length,
    path,
  });
}

export function saveArtifactData(
  homeDir: string,
  input: { name: string; mimeType: string; data: Buffer },
): Artifact {
  if (input.data.length === 0) throw new Error("Artifact is empty.");
  const id = randomUUID();
  const name = safeName(input.name);
  const extension = extname(name) || extensionFor(input.mimeType);
  const directory = join(homeDir, "artifacts");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  chmodSync(directory, 0o700);
  const path = join(directory, `${id}${extension}`);
  writeFileSync(path, input.data, { mode: 0o600, flag: "wx" });
  return { id, kind: input.mimeType.startsWith("image/") ? "image" : "file", name, mimeType: input.mimeType, size: input.data.length, path };
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
  const id = randomUUID();
  const directory = join(homeDir, "artifacts");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  chmodSync(directory, 0o700);
  const path = join(directory, `${id}${extension}`);
  copyFileSync(source, path);
  chmodSync(path, 0o600);
  return { id, kind: mimeType.startsWith("image/") ? "image" : "file", name, mimeType, size: sourceStat.size, path };
}

function mimeForExtension(extension: string): string {
  const known: Record<string, string> = {
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp",
    ".gif": "image/gif", ".pdf": "application/pdf", ".txt": "text/plain", ".md": "text/markdown",
    ".json": "application/json", ".zip": "application/zip",
  };
  return known[extension.toLowerCase()] ?? "application/octet-stream";
}
