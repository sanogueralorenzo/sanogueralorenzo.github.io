import type { ChatService } from "./config-types.js";

function slugify(value: string): string {
	return value
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "")
		.slice(0, 48);
}

export function makeAccountKey(service: ChatService, label: string): string {
	const base = slugify(label) || service;
	return `${service}-${base}`;
}

export function makeChannelKey(label: string, fallbackId: string): string {
	return slugify(label) || fallbackId;
}
