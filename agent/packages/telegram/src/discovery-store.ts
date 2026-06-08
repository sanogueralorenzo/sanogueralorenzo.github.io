import { readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { CHAT_CACHE_DIR, ensureChatHome } from "./config.js";
import type { DiscoverySnapshot } from "./core/discovery-types.js";

function sanitizePathSegment(value: string): string {
	return value.replace(/[^a-zA-Z0-9._-]+/g, "_");
}

export function getDiscoverySnapshotPath(accountId: string): string {
	return join(CHAT_CACHE_DIR, `${sanitizePathSegment(accountId)}.json`);
}

export async function loadDiscoverySnapshot(accountId: string): Promise<DiscoverySnapshot | undefined> {
	await ensureChatHome();
	try {
		const content = await readFile(getDiscoverySnapshotPath(accountId), "utf8");
		return JSON.parse(content) as DiscoverySnapshot;
	} catch {
		return undefined;
	}
}

export async function removeDiscoverySnapshot(accountId: string): Promise<void> {
	await ensureChatHome();
	await rm(getDiscoverySnapshotPath(accountId), { force: true });
}

export async function saveDiscoverySnapshot(snapshot: DiscoverySnapshot): Promise<void> {
	await ensureChatHome();
	await writeFile(getDiscoverySnapshotPath(snapshot.accountId), `${JSON.stringify(snapshot, null, "\t")}\n`, "utf8");
}
