import { constants, createDecipheriv, generateKeyPairSync, privateDecrypt } from "node:crypto";

export interface PendingSecretRequest {
	name: string;
	privateKeyPem: string;
}

const pendingSecrets = new Map<string, PendingSecretRequest>();

export function createSecretRequest(name: string, description: string): { requestId: string; widgetUrl: string } {
	const { publicKey, privateKey } = generateKeyPairSync("rsa", {
		modulusLength: 2048,
		publicKeyEncoding: { type: "spki", format: "der" },
		privateKeyEncoding: { type: "pkcs8", format: "pem" },
	});
	const requestId = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
	pendingSecrets.set(requestId, { name, privateKeyPem: privateKey as string });
	const pubB64 = (publicKey as Buffer).toString("base64");
	const hash = Buffer.from(JSON.stringify({ n: name, d: description, k: pubB64, r: requestId })).toString("base64");
	return { requestId, widgetUrl: `https://pi.dev/secret#${hash}` };
}

export function tryDecryptSecret(text: string): { requestId: string; name: string; decrypted: string } | undefined {
	const match = text.match(/!secret:([^:]+):([A-Za-z0-9+/=]+)/);
	if (!match) return undefined;
	const [, requestId, payload] = match;
	const pending = pendingSecrets.get(requestId);
	if (!pending) return undefined;
	try {
		const buf = Buffer.from(payload, "base64");
		const kl = buf.readUInt16BE(0);
		const ek = buf.subarray(2, 2 + kl);
		const r = buf.subarray(2 + kl);
		const iv = r.subarray(0, 12);
		const tag = r.subarray(r.length - 16);
		const ct = r.subarray(12, r.length - 16);
		const aes = privateDecrypt(
			{ key: pending.privateKeyPem, padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: "sha256" },
			ek,
		);
		const d = createDecipheriv("aes-256-gcm", aes, iv);
		d.setAuthTag(tag);
		const decrypted = Buffer.concat([d.update(ct), d.final()]).toString("utf8");
		pendingSecrets.delete(requestId);
		return { requestId, name: pending.name, decrypted };
	} catch {
		return undefined;
	}
}
