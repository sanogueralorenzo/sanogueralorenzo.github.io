import type { ExtensionContext } from "@mariozechner/pi-coding-agent";
import { BorderedLoader } from "@mariozechner/pi-coding-agent";

import { saveChatConfig } from "../config.js";
import type { ChatConfig, DiscordAccountConfig } from "../core/config-types.js";
import { makeAccountKey } from "../core/keys.js";
import { buildDiscordInviteUrl, listDiscordServers, waitForDiscordServerJoin } from "../services/discord.js";
import { refreshAccountSnapshot, updateAccountIdentityFromSnapshot, validateAccountDraft } from "../services/index.js";
import { runWithLoader, selectItem, showNotice } from "./dialogs.js";

interface DiscordDraft {
	name: string;
	botToken: string;
}

async function waitForServerInvite(
	ctx: ExtensionContext,
	botToken: string,
	applicationId: string,
	knownServerIds: string[],
): Promise<{ id: string; name: string } | undefined> {
	const inviteUrl = buildDiscordInviteUrl(applicationId);
	return ctx.ui.custom<{ id: string; name: string } | undefined>((tui, theme, _kb, done) => {
		const loader = new BorderedLoader(
			tui,
			theme,
			`Invite the bot to a Discord server using:\n${inviteUrl}\n\nWaiting for the bot to join a server...`,
			{ cancellable: true },
		);
		loader.onAbort = () => done(undefined);
		void (async () => {
			try {
				const joined = await waitForDiscordServerJoin(botToken, knownServerIds, loader.signal);
				done(joined);
			} catch (error) {
				if (loader.signal.aborted) {
					done(undefined);
					return;
				}
				ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				done(undefined);
			}
		})();
		return loader;
	});
}

function ensureUniqueKey(existing: Record<string, unknown>, base: string): string {
	if (!existing[base]) return base;
	let index = 2;
	while (existing[`${base}-${index}`]) index += 1;
	return `${base}-${index}`;
}

async function promptDiscordDraft(ctx: ExtensionContext): Promise<DiscordDraft | undefined> {
	const label = await ctx.ui.input("Discord account label", "discord-bot");
	if (label === undefined) return undefined;
	const botToken = await ctx.ui.input("Discord bot token", "");
	if (botToken === undefined || !botToken.trim()) return undefined;
	return { name: label.trim() || "discord-bot", botToken: botToken.trim() };
}

async function pickDiscordServer(
	ctx: ExtensionContext,
	botToken: string,
	applicationId: string,
	servers: Array<{ id: string; name: string }>,
): Promise<{ id: string; name: string } | undefined> {
	while (true) {
		const choice = await selectItem(ctx, "Pick Discord server for this account", [
			...servers.map((server) => ({ value: server.id, label: server.name, description: server.id })),
			{
				value: "__invite__",
				label: "Invite bot to a new server",
				description: "Open invite URL and wait for bot to join",
			},
			{ value: "__cancel__", label: "Cancel" },
		]);
		if (!choice || choice === "__cancel__") return undefined;
		if (choice === "__invite__") {
			const joined = await waitForServerInvite(
				ctx,
				botToken,
				applicationId,
				servers.map((server) => server.id),
			);
			if (!joined) return undefined;
			servers = [...servers, joined].sort((a, b) => a.name.localeCompare(b.name));
			return joined;
		}
		return servers.find((server) => server.id === choice);
	}
}

export async function createDiscordAccountWithGuidedSetup(
	ctx: ExtensionContext,
	config: ChatConfig,
): Promise<string | undefined> {
	const draft = await promptDiscordDraft(ctx);
	if (!draft) return undefined;
	const validation = await runWithLoader(ctx, "Validating Discord bot token...", () =>
		validateAccountDraft({ service: "discord", botToken: draft.botToken, name: draft.name }),
	);
	if (validation.error) {
		await showNotice(ctx, "Discord setup error", validation.error, "error");
		return undefined;
	}
	if (!validation.value) return undefined;
	const serversResult = await runWithLoader(ctx, "Fetching Discord servers...", () =>
		listDiscordServers(draft.botToken),
	);
	if (serversResult.error) {
		await showNotice(ctx, "Discord setup error", serversResult.error, "error");
		return undefined;
	}
	const applicationId = validation.value.identity.id;
	let currentServers = serversResult.value ?? [];
	if (currentServers.length === 0) {
		const joined = await waitForServerInvite(ctx, draft.botToken, applicationId, []);
		if (!joined) return undefined;
		currentServers = [joined];
	}
	const selectedServer = await pickDiscordServer(ctx, draft.botToken, applicationId, currentServers);
	if (!selectedServer) return undefined;
	const key = ensureUniqueKey(config.accounts, makeAccountKey("discord", draft.name || selectedServer.name));
	let account: DiscordAccountConfig = {
		service: "discord",
		name: draft.name,
		botToken: draft.botToken,
		applicationId,
		serverId: selectedServer.id,
		serverName: selectedServer.name,
		channels: {},
		access: { ignoreBots: true },
	};
	const snapshot = await runWithLoader(ctx, `Discovering channels in ${selectedServer.name}...`, () =>
		refreshAccountSnapshot(key, account),
	);
	if (snapshot.error) {
		await showNotice(ctx, "Discord setup error", snapshot.error, "error");
		return undefined;
	}
	if (!snapshot.value) return undefined;
	account = updateAccountIdentityFromSnapshot(account, snapshot.value) as DiscordAccountConfig;
	config.accounts[key] = account;
	await saveChatConfig(config);
	await showNotice(ctx, "Discord account created", `Created ${key}`, "info");
	return key;
}
