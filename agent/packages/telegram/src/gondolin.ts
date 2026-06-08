import { randomUUID } from "node:crypto";
import { constants as fsConstants, realpathSync } from "node:fs";
import { access, mkdir, open, readdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";

import { createHttpHooks, RealFSProvider, type SecretDefinition, VM } from "@earendil-works/gondolin";

import type { ResolvedConversation } from "./core/config-types.js";
import { ensureConversationDirs } from "./log.js";

export const GONDOLIN_WORKSPACE = "/workspace";
export const GONDOLIN_SHARED = "/shared";

function toPosix(value: string): string {
	return value.split(path.sep).join(path.posix.sep);
}

function isInside(root: string, value: string): boolean {
	const rel = path.relative(root, value);
	return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
}

function guestMountRoot(guestPath: string): typeof GONDOLIN_WORKSPACE | typeof GONDOLIN_SHARED | undefined {
	if (guestPath === GONDOLIN_WORKSPACE || guestPath.startsWith(`${GONDOLIN_WORKSPACE}/`)) return GONDOLIN_WORKSPACE;
	if (guestPath === GONDOLIN_SHARED || guestPath.startsWith(`${GONDOLIN_SHARED}/`)) return GONDOLIN_SHARED;
	return undefined;
}

function resolveSecretEnvironment(conversation: ResolvedConversation): {
	env?: Record<string, string>;
	httpHooks?: ReturnType<typeof createHttpHooks>["httpHooks"];
	configuredSecretNames: string[];
} {
	const configuredSecretNames = Object.keys(conversation.gondolinSecrets);
	if (configuredSecretNames.length === 0) return { configuredSecretNames };
	const secrets: Record<string, SecretDefinition> = {};
	for (const [name, secret] of Object.entries(conversation.gondolinSecrets)) {
		if (!secret.value.trim()) throw new Error(`Gondolin secret ${name} must have a value`);
		if (secret.hosts.length === 0) throw new Error(`Gondolin secret ${name} must declare at least one host`);
		secrets[name] = { hosts: [...secret.hosts], value: secret.value };
	}
	const { env, httpHooks } = createHttpHooks({ allowedHosts: ["*"], secrets });
	return { env, httpHooks, configuredSecretNames };
}

async function walk(
	root: string,
	current: string,
	visit: (absolutePath: string, relativePath: string) => Promise<boolean>,
): Promise<void> {
	const entries = await readdir(current, { withFileTypes: true });
	for (const entry of entries) {
		if (entry.name === ".git" || entry.name === "node_modules" || entry.isSymbolicLink()) continue;
		const absolutePath = path.join(current, entry.name);
		const relativePath = toPosix(path.relative(root, absolutePath));
		const shouldDescend = await visit(absolutePath, relativePath);
		if (shouldDescend && entry.isDirectory()) await walk(root, absolutePath, visit);
	}
}

export class ConversationSandbox {
	readonly conversation: ResolvedConversation;
	private vm: VM | undefined;
	private starting: Promise<VM> | undefined;

	constructor(conversation: ResolvedConversation) {
		this.conversation = conversation;
	}

	async start(): Promise<VM> {
		if (this.vm) return this.vm;
		if (this.starting) return this.starting;
		this.starting = (async () => {
			await ensureConversationDirs(this.conversation);
			const secretConfig = resolveSecretEnvironment(this.conversation);
			const vm = await VM.create({
				sessionLabel: `pi-chat ${this.conversation.conversationName}`,
				env: secretConfig.env,
				httpHooks: secretConfig.httpHooks,
				vfs: {
					mounts: {
						[GONDOLIN_WORKSPACE]: new RealFSProvider(this.conversation.workspaceDir),
						[GONDOLIN_SHARED]: new RealFSProvider(this.conversation.sharedDir),
					},
				},
			});
			await vm.exec("command -v bash > /dev/null 2>&1 || apk add --no-cache bash > /dev/null 2>&1 || true");
			this.vm = vm;
			this.starting = undefined;
			await writeFile(
				path.join(this.conversation.gondolinDir, "session.json"),
				`${JSON.stringify({ vmId: vm.id, secretNames: secretConfig.configuredSecretNames }, null, "\t")}\n`,
				"utf8",
			);
			return vm;
		})();
		return this.starting;
	}

	async close(): Promise<void> {
		const vm = this.vm;
		this.vm = undefined;
		this.starting = undefined;
		if (vm) await vm.close();
	}

	private resolveGuestPath(inputPath: string): string {
		const trimmed = inputPath.trim();
		if (!trimmed) throw new Error("Path must not be empty");
		const base = trimmed.startsWith("/") ? "/" : GONDOLIN_WORKSPACE;
		const guestPath = path.posix.resolve(base, trimmed);
		if (!guestMountRoot(guestPath)) throw new Error(`Path is outside mounted storage: ${inputPath}`);
		return guestPath;
	}

	async stageAttachment(inputPath: string): Promise<string> {
		const sourcePath = this.guestToHostPath(inputPath);
		const handle = await open(sourcePath, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
		try {
			const fileStats = await handle.stat();
			if (!fileStats.isFile()) throw new Error(`Not a file: ${inputPath}`);
			const stagingDir = path.join(this.conversation.gondolinDir, "outgoing");
			await mkdir(stagingDir, { recursive: true });
			const safeName = path.basename(sourcePath).replace(/[^a-zA-Z0-9._-]+/g, "_") || "attachment";
			const stagedPath = path.join(stagingDir, `${Date.now()}-${randomUUID()}-${safeName}`);
			await writeFile(stagedPath, await handle.readFile(), { flag: "wx" });
			return stagedPath;
		} finally {
			await handle.close();
		}
	}

	resolveToolPath(inputPath: string): string {
		return this.resolveGuestPath(inputPath);
	}

	guestToHostPath(inputPath: string): string {
		const guestPath = this.resolveGuestPath(inputPath);
		const mountRoot = guestMountRoot(guestPath);
		let hostRoot: string;
		let hostPath: string;
		if (mountRoot === GONDOLIN_WORKSPACE) {
			const relativePath = path.posix.relative(GONDOLIN_WORKSPACE, guestPath);
			hostRoot = this.conversation.workspaceDir;
			hostPath = path.join(hostRoot, ...relativePath.split("/").filter(Boolean));
		} else if (mountRoot === GONDOLIN_SHARED) {
			const relativePath = path.posix.relative(GONDOLIN_SHARED, guestPath);
			hostRoot = this.conversation.sharedDir;
			hostPath = path.join(hostRoot, ...relativePath.split("/").filter(Boolean));
		} else {
			throw new Error(`Path is outside mounted storage: ${inputPath}`);
		}
		const resolvedRoot = realpathSync(hostRoot);
		const resolvedHostPath = realpathSync(hostPath);
		if (!isInside(resolvedRoot, resolvedHostPath)) throw new Error(`Path is outside mounted storage: ${inputPath}`);
		return resolvedHostPath;
	}

	private assertMountedHostPath(hostPath: string): string {
		const resolved = realpathSync(hostPath);
		const workspaceRoot = realpathSync(this.conversation.workspaceDir);
		if (isInside(workspaceRoot, resolved)) return resolved;
		const sharedRoot = realpathSync(this.conversation.sharedDir);
		if (isInside(sharedRoot, resolved)) return resolved;
		throw new Error(`Path is outside mounted storage: ${hostPath}`);
	}

	hostToGuestPath(hostPath: string): string {
		const resolved = this.assertMountedHostPath(hostPath);
		const workspaceRoot = realpathSync(this.conversation.workspaceDir);
		if (isInside(workspaceRoot, resolved)) {
			const relativePath = toPosix(path.relative(workspaceRoot, resolved));
			return relativePath ? path.posix.join(GONDOLIN_WORKSPACE, relativePath) : GONDOLIN_WORKSPACE;
		}
		const sharedRoot = realpathSync(this.conversation.sharedDir);
		if (isInside(sharedRoot, resolved)) {
			const relativePath = toPosix(path.relative(sharedRoot, resolved));
			return relativePath ? path.posix.join(GONDOLIN_SHARED, relativePath) : GONDOLIN_SHARED;
		}
		throw new Error(`Path is outside mounted storage: ${hostPath}`);
	}

	async createReadOperations() {
		const vm = await this.start();
		return {
			readFile: async (guestPath: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				return vm.fs.readFile(resolvedPath);
			},
			access: async (guestPath: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				await vm.fs.access(resolvedPath);
			},
			detectImageMimeType: async (guestPath: string) => {
				const ext = path.posix.extname(this.resolveGuestPath(guestPath)).toLowerCase();
				if (ext === ".png") return "image/png";
				if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
				if (ext === ".gif") return "image/gif";
				if (ext === ".webp") return "image/webp";
				return null;
			},
		};
	}

	async createWriteOperations() {
		const vm = await this.start();
		return {
			writeFile: async (guestPath: string, content: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				await vm.fs.writeFile(resolvedPath, content);
			},
			mkdir: async (guestPath: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				await vm.fs.mkdir(resolvedPath, { recursive: true });
			},
		};
	}

	async createEditOperations() {
		const vm = await this.start();
		return {
			readFile: async (guestPath: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				return vm.fs.readFile(resolvedPath);
			},
			writeFile: async (guestPath: string, content: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				await vm.fs.writeFile(resolvedPath, content);
			},
			access: async (guestPath: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				await vm.fs.access(resolvedPath);
			},
		};
	}

	async createLsOperations() {
		const vm = await this.start();
		return {
			exists: async (guestPath: string) => {
				try {
					const resolvedPath = this.resolveGuestPath(guestPath);
					await vm.fs.access(resolvedPath);
					return true;
				} catch {
					return false;
				}
			},
			stat: async (guestPath: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				return vm.fs.stat(resolvedPath);
			},
			readdir: async (guestPath: string) => {
				const resolvedPath = this.resolveGuestPath(guestPath);
				return vm.fs.listDir(resolvedPath);
			},
		};
	}

	async createFindOperations() {
		return {
			exists: async (guestPath: string) => {
				try {
					await access(this.guestToHostPath(guestPath));
					return true;
				} catch {
					return false;
				}
			},
			glob: async (pattern: string, guestCwd: string, options: { ignore: string[]; limit: number }) => {
				const rootHostPath = this.guestToHostPath(guestCwd);
				const results: string[] = [];
				await walk(rootHostPath, rootHostPath, async (absolutePath, relativePath) => {
					if (results.length >= options.limit) return false;
					const entryStat = await stat(absolutePath);
					if (entryStat.isDirectory()) return true;
					const basename = path.posix.basename(relativePath);
					const matches = pattern.includes("/")
						? path.matchesGlob(relativePath, pattern)
						: path.matchesGlob(basename, pattern);
					if (matches) results.push(this.hostToGuestPath(absolutePath));
					return false;
				});
				return results;
			},
		};
	}

	async createGrepOperations() {
		return {
			isDirectory: async (hostPath: string) => (await stat(this.assertMountedHostPath(hostPath))).isDirectory(),
			readFile: async (hostPath: string) => readFile(this.assertMountedHostPath(hostPath), "utf8"),
		};
	}

	async createBashOperations() {
		const vm = await this.start();
		return {
			exec: async (
				command: string,
				cwd: string,
				options: { onData: (data: Buffer) => void; signal?: AbortSignal; timeout?: number; env?: NodeJS.ProcessEnv },
			) => {
				const guestCwd = this.resolveGuestPath(cwd);
				const controller = new AbortController();
				const onAbort = () => controller.abort();
				options.signal?.addEventListener("abort", onAbort, { once: true });
				let timedOut = false;
				const timer =
					options.timeout && options.timeout > 0
						? setTimeout(() => {
								timedOut = true;
								controller.abort();
							}, options.timeout * 1000)
						: undefined;
				try {
					const proc = vm.exec(["/bin/bash", "-lc", command], {
						cwd: guestCwd,
						signal: controller.signal,
						stdout: "pipe",
						stderr: "pipe",
					});
					for await (const chunk of proc.output()) options.onData(chunk.data);
					const result = await proc;
					return { exitCode: result.exitCode };
				} catch (error) {
					if (options.signal?.aborted) throw new Error("aborted");
					if (timedOut) throw new Error(`timeout:${options.timeout}`);
					throw error;
				} finally {
					if (timer) clearTimeout(timer);
					options.signal?.removeEventListener("abort", onAbort);
				}
			},
		};
	}
}
