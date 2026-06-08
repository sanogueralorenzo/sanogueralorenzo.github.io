import type { ExtensionContext } from "@mariozechner/pi-coding-agent";

import {
	CHAT_CONFIG_PATH,
	loadChatConfig,
	removeAccountStorage,
	removeChannelStorage,
	saveChatConfig,
} from "../config.js";
import type { AccessPolicy, ChatAccountConfig, ChatConfig, TelegramAccountConfig } from "../core/config-types.js";
import type { DiscoveredRole, DiscoveredUser, DiscoverySnapshot } from "../core/discovery-types.js";
import { loadDiscoverySnapshot } from "../discovery-store.js";
import { refreshAccountSnapshot, updateAccountIdentityFromSnapshot } from "../services/index.js";
import { selectItem, showNotice, toggleItems } from "./dialogs.js";
import { addTelegramObservedTargetToAccount, createTelegramAccountWithGuidedSetup } from "./telegram-setup.js";

function accountDescription(account: ChatAccountConfig, snapshot: DiscoverySnapshot | undefined): string {
	const parts: string[] = [account.service];
	if (account.name) parts.push(account.name);
	if (snapshot?.identity.userName) parts.push(`@${snapshot.identity.userName}`);
	parts.push(
		`${Object.keys(account.channels).length} configured channel${Object.keys(account.channels).length === 1 ? "" : "s"}`,
	);
	return parts.join(" • ");
}

function toUserToggleItems(
	users: DiscoveredUser[],
	selectedIds: string[] = [],
): Array<{ id: string; label: string; description?: string }> {
	const items = new Map<string, { id: string; label: string; description?: string }>();
	for (const user of users) {
		items.set(user.id, {
			id: user.id,
			label: user.displayName || user.name,
			description: user.displayName && user.displayName !== user.name ? user.name : undefined,
		});
	}
	for (const id of selectedIds) if (!items.has(id)) items.set(id, { id, label: id, description: "stored id" });
	return [...items.values()].sort((a, b) => a.label.localeCompare(b.label));
}

function toRoleToggleItems(
	roles: DiscoveredRole[],
	selectedIds: string[] = [],
): Array<{ id: string; label: string; description?: string }> {
	const items = new Map<string, { id: string; label: string; description?: string }>();
	for (const role of roles) items.set(role.id, { id: role.id, label: role.name });
	for (const id of selectedIds) if (!items.has(id)) items.set(id, { id, label: id, description: "stored id" });
	return [...items.values()].sort((a, b) => a.label.localeCompare(b.label));
}

function defaultAccess(dm: boolean): AccessPolicy {
	return { trigger: dm ? "message" : "mention", ignoreBots: true };
}

async function promptAccessPolicy(
	ctx: ExtensionContext,
	current: AccessPolicy,
	snapshot: DiscoverySnapshot | undefined,
	dm: boolean,
): Promise<AccessPolicy | undefined> {
	let policy: AccessPolicy = { ...current };
	while (true) {
		const choice = await selectItem(ctx, "Access policy", [
			{ value: "trigger", label: `Trigger: ${policy.trigger ?? (dm ? "message" : "mention")}` },
			{ value: "bots", label: `Ignore bots: ${(policy.ignoreBots ?? true) ? "yes" : "no"}` },
			{ value: "users", label: `Allowed users: ${policy.allowedUserIds?.length ?? 0}` },
			{ value: "roles", label: `Allowed roles: ${policy.allowedRoleIds?.length ?? 0}` },
			{ value: "save", label: "Save" },
			{ value: "cancel", label: "Cancel" },
		]);
		if (!choice || choice === "cancel") return undefined;
		if (choice === "save") return policy;
		if (choice === "trigger") {
			const selected = await selectItem(ctx, "Trigger mode", [
				{ value: "mention", label: "Mention", description: "Only @mentions create jobs" },
				{
					value: "message",
					label: "Message",
					description: dm ? "Every DM message creates a job" : "Every matching message creates a job",
				},
			]);
			if (selected) policy = { ...policy, trigger: selected as AccessPolicy["trigger"] };
			continue;
		}
		if (choice === "bots") {
			policy = {
				...policy,
				ignoreBots: await ctx.ui.confirm(
					"Ignore bot messages",
					`Current value: ${(policy.ignoreBots ?? true) ? "yes" : "no"}`,
				),
			};
			continue;
		}
		if (choice === "users") {
			const items = toUserToggleItems(snapshot?.users ?? [], policy.allowedUserIds ?? []);
			if (items.length === 0) {
				await showNotice(ctx, "No discovered users", "No discovered users available for this account.", "warning");
				continue;
			}
			const selected = await toggleItems(ctx, "Allowed users", items, policy.allowedUserIds ?? []);
			if (selected) policy = { ...policy, allowedUserIds: selected.length > 0 ? selected : undefined };
			continue;
		}
		if (choice === "roles") {
			const items = toRoleToggleItems(snapshot?.roles ?? [], policy.allowedRoleIds ?? []);
			if (items.length === 0) {
				await showNotice(ctx, "No discovered roles", "No discovered roles available for this account.", "warning");
				continue;
			}
			const selected = await toggleItems(ctx, "Allowed roles", items, policy.allowedRoleIds ?? []);
			if (selected) policy = { ...policy, allowedRoleIds: selected.length > 0 ? selected : undefined };
		}
	}
}

async function configureConfiguredChannel(
	ctx: ExtensionContext,
	config: ChatConfig,
	accountId: string,
	channelKey: string,
): Promise<void> {
	const account = config.accounts[accountId];
	const channel = account?.channels[channelKey];
	if (!account || !channel) return;
	const snapshot = await loadDiscoverySnapshot(accountId);
	while (true) {
		const choice = await selectItem(ctx, `${accountId}/${channelKey}`, [
			{ value: "access", label: "Edit access policy" },
			{ value: "delete", label: "Delete channel", description: "Remove this configured channel" },
			{ value: "back", label: "Back" },
		]);
		if (!choice || choice === "back") return;
		if (choice === "access") {
			const access = await promptAccessPolicy(
				ctx,
				channel.access ?? defaultAccess(channel.dm ?? false),
				snapshot,
				channel.dm ?? false,
			);
			if (!access) continue;
			channel.access = access;
			account.channels[channelKey] = channel;
			await saveChatConfig(config);
			await showNotice(ctx, "Channel updated", `Updated ${accountId}/${channelKey}`, "info");
			continue;
		}
		if (choice === "delete") {
			const ok = await ctx.ui.confirm("Delete configured channel", `Delete ${accountId}/${channelKey}?`);
			if (!ok) continue;
			delete account.channels[channelKey];
			await saveChatConfig(config);
			await removeChannelStorage(accountId, channelKey, ctx.cwd);
			await showNotice(ctx, "Channel deleted", `Deleted ${accountId}/${channelKey}`, "info");
			return;
		}
	}
}

async function configureTelegramAccount(ctx: ExtensionContext, accountId: string): Promise<void> {
	while (true) {
		const config = await loadChatConfig();
		const account = config.accounts[accountId] as TelegramAccountConfig | undefined;
		if (!account || account.service !== "telegram") return;
		const channelChoices = Object.entries(account.channels).map(([key, channel]) => ({
			value: key,
			label: key,
			description: `${channel.name ?? channel.id}${channel.dm ? " • dm" : " • group"}`,
		}));
		const choice = await selectItem(ctx, `${accountId} (@${account.botUsername ?? "bot"})`, [
			{ value: "add-dm", label: "Add DM", description: "Pair a DM by sending /start to the bot" },
			{ value: "add-group", label: "Add group", description: "Observe activity after adding the bot to a group" },
			{ value: "refresh", label: "Refresh bot info" },
			{ value: "delete", label: "Delete account", description: "Remove account and all configured channels" },
			...channelChoices,
			{ value: "back", label: "Back" },
		]);
		if (!choice || choice === "back") return;
		if (choice === "add-dm") {
			await addTelegramObservedTargetToAccount(ctx, config, accountId, account, "dm");
			continue;
		}
		if (choice === "add-group") {
			await addTelegramObservedTargetToAccount(ctx, config, accountId, account, "group");
			continue;
		}
		if (choice === "refresh") {
			const fresh = await refreshAccountSnapshot(accountId, account);
			config.accounts[accountId] = updateAccountIdentityFromSnapshot(account, fresh);
			await saveChatConfig(config);
			continue;
		}
		if (choice === "delete") {
			const ok = await ctx.ui.confirm("Delete account", `Delete ${accountId} and all configured channels?`);
			if (!ok) continue;
			delete config.accounts[accountId];
			await saveChatConfig(config);
			await removeAccountStorage(accountId, ctx.cwd);
			await showNotice(ctx, "Account deleted", `Deleted ${accountId}`, "info");
			return;
		}
		await configureConfiguredChannel(ctx, config, accountId, choice);
	}
}

async function configureAccount(ctx: ExtensionContext, accountId: string): Promise<void> {
	const config = await loadChatConfig();
	const account = config.accounts[accountId];
	if (!account) return;
	if (account.service === "telegram") return configureTelegramAccount(ctx, accountId);
}

export async function runChatConfigUI(ctx: ExtensionContext): Promise<void> {
	if (!ctx.hasUI) {
		ctx.ui.notify(CHAT_CONFIG_PATH, "info");
		return;
	}
	while (true) {
		const config = await loadChatConfig();
		const snapshots = await Promise.all(
			Object.keys(config.accounts)
				.sort()
				.map(async (accountId) => ({ accountId, snapshot: await loadDiscoverySnapshot(accountId) })),
		);
		const choice = await selectItem(ctx, "pi-chat accounts", [
			...snapshots.map(({ accountId, snapshot }) => ({
				value: accountId,
				label: accountId,
				description: accountDescription(config.accounts[accountId], snapshot),
			})),
			{ value: "__create__", label: "+ Create account", description: "Create a Telegram account" },
		]);
		if (!choice) return;
		if (choice === "__create__") {
			const accountId = await createTelegramAccountWithGuidedSetup(ctx, config);
			if (accountId) await configureAccount(ctx, accountId);
			continue;
		}
		await configureAccount(ctx, choice);
	}
}
