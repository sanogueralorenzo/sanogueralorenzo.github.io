import { once } from "node:events";

import { ChannelType, Client, GatewayIntentBits, Partials } from "discord.js";

import type { DiscordAccountConfig } from "../core/config-types.js";
import type {
	AccountValidationResult,
	DiscoveredChannel,
	DiscoveredRole,
	DiscoveredUser,
	DiscoverySnapshot,
} from "../core/discovery-types.js";
import type { AccountDraft, DiscoveryProvider } from "./types.js";

interface DiscordServerInfo {
	id: string;
	name: string;
}

async function withDiscordClient<T>(token: string, work: (client: Client<true>) => Promise<T>): Promise<T> {
	const client = new Client({
		intents: [GatewayIntentBits.Guilds],
		partials: [Partials.Channel],
	});
	try {
		const readyPromise = once(client, "ready");
		await client.login(token);
		if (!client.isReady()) {
			await Promise.race([
				readyPromise,
				new Promise((_, reject) => setTimeout(() => reject(new Error("Discord client failed to become ready")), 10000)),
			]);
		}
		if (!client.isReady()) throw new Error("Discord client failed to become ready");
		return await work(client as Client<true>);
	} finally {
		client.destroy();
	}
}

export async function listDiscordServers(token: string): Promise<DiscordServerInfo[]> {
	return withDiscordClient(token, async (client) =>
		[...client.guilds.cache.values()]
			.map((guild) => ({ id: guild.id, name: guild.name }))
			.sort((a, b) => a.name.localeCompare(b.name)),
	);
}

export async function waitForDiscordServerJoin(
	token: string,
	knownServerIds: string[],
	signal?: AbortSignal,
): Promise<DiscordServerInfo> {
	return withDiscordClient(token, async (client) => {
		const known = new Set(knownServerIds);
		for (const guild of client.guilds.cache.values()) {
			if (!known.has(guild.id)) return { id: guild.id, name: guild.name };
		}
		return await new Promise<DiscordServerInfo>((resolve, reject) => {
			const onAbort = () => {
				client.off("guildCreate", onGuildCreate);
				reject(new Error("Cancelled Discord server invite wait"));
			};
			const onGuildCreate = (guild: { id: string; name: string }) => {
				if (signal) signal.removeEventListener("abort", onAbort);
				resolve({ id: guild.id, name: guild.name });
			};
			client.on("guildCreate", onGuildCreate);
			signal?.addEventListener("abort", onAbort, { once: true });
		});
	});
}

export function buildDiscordInviteUrl(applicationId: string): string {
	const permissions = "274878303296";
	return `https://discord.com/oauth2/authorize?client_id=${applicationId}&scope=bot&permissions=${permissions}`;
}

export const discordDiscoveryProvider: DiscoveryProvider = {
	service: "discord",
	async validate(draft: AccountDraft): Promise<AccountValidationResult> {
		return withDiscordClient(draft.botToken, async (client) => ({
			identity: {
				id: client.user.id,
				name: client.user.globalName || client.user.username,
				userName: client.user.username,
			},
			warnings: undefined,
		}));
	},
	async fetchSnapshot(accountId: string, account: DiscordAccountConfig): Promise<DiscoverySnapshot> {
		return withDiscordClient(account.botToken, async (client) => {
			const guildRef = client.guilds.cache.get(account.serverId);
			if (!guildRef) {
				return {
					accountId,
					service: "discord",
					fetchedAt: new Date().toISOString(),
					identity: {
						id: client.user.id,
						name: client.user.globalName || client.user.username,
						userName: client.user.username,
					},
					channels: [],
					users: [],
					roles: [],
					warnings: [
						`Bot is not currently in the configured Discord server ${account.serverName ?? account.serverId}. Recreate the account or re-invite the bot.`,
					],
					capabilities: {
						canListChannels: false,
						canListThreads: false,
						canListUsers: false,
						canListRoles: false,
					},
				};
			}
			const guild = await guildRef.fetch();
			const fetchedChannels = await guild.channels.fetch();
			const channels: DiscoveredChannel[] = [];
			const roles: DiscoveredRole[] = [];
			const users: DiscoveredUser[] = [];
			for (const channel of fetchedChannels.values()) {
				if (!channel) continue;
				if (channel.type !== ChannelType.GuildText && channel.type !== ChannelType.GuildAnnouncement) continue;
				channels.push({
					id: channel.id,
					name: channel.name,
				});
			}
			const fetchedRoles = await guild.roles.fetch();
			for (const role of fetchedRoles.values()) {
				if (!role || role.name === "@everyone") continue;
				roles.push({ id: role.id, name: role.name });
			}
			return {
				accountId,
				service: "discord",
				fetchedAt: new Date().toISOString(),
				identity: {
					id: client.user.id,
					name: client.user.globalName || client.user.username,
					userName: client.user.username,
					workspaceId: guild.id,
					workspaceName: guild.name,
				},
				channels: channels.sort((a, b) => a.name.localeCompare(b.name)),
				users,
				roles: roles.sort((a, b) => a.name.localeCompare(b.name)),
				capabilities: {
					canListChannels: channels.length > 0,
					canListUsers: false,
					canListRoles: roles.length > 0,
				},
			};
		});
	},
};
