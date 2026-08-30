import { createInterface } from 'node:readline';
import { randomBytes } from 'node:crypto';
import { mkdir } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { EncryptedJsonClipboardStore } from './encrypted-clipboard-store.ts';
import { JsonRunHistoryStore } from './file-stores.ts';
import { PolicyClipboardHistory } from './clipboard-history.ts';
import { PaletteService } from './service.ts';
import { handleBridgeRequest } from './service-bridge.ts';
import type { BridgeRequest, BridgeResponse } from './bridge-protocol.ts';
import type { Notification } from './contracts.ts';

const dataDirectory = process.env.PALETTE_DATA_DIR || join(homedir(), '.palette');
const configuredKey = process.env.PALETTE_CLIPBOARD_KEY;
const encryptionKey = configuredKey ? Buffer.from(configuredKey, 'base64') : randomBytes(32);
if (encryptionKey.length !== 32) throw new Error('PALETTE_CLIPBOARD_KEY must be a base64-encoded 32-byte key');
await mkdir(dataDirectory, { recursive: true });

function notify(_notification: Notification): Promise<void> {
  // Notifications are returned with the command result. A native host can add
  // OS notifications later without changing the service protocol.
  return Promise.resolve();
}

function writeClipboard(content: string): Promise<void> {
  const command = process.platform === 'darwin' ? 'pbcopy' : process.platform === 'win32' ? 'clip' : 'xclip';
  const args = process.platform === 'darwin' || process.platform === 'win32' ? [] : ['-selection', 'clipboard'];
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['pipe', 'ignore', 'pipe'], windowsHide: true });
    let error = '';
    child.stderr.on('data', (chunk) => { error += chunk.toString(); });
    child.once('error', reject);
    child.once('close', (code) => code === 0 ? resolve() : reject(new Error(error || `Clipboard command exited with ${code ?? 'unknown'}`)));
    child.stdin.end(content);
  });
}

const service = new PaletteService({
  platform: process.platform === 'darwin' ? 'macos' : process.platform === 'win32' ? 'windows' : 'linux',
  host: { setMenubarIcon: async () => {}, notify, writeClipboard },
  history: new JsonRunHistoryStore(join(dataDirectory, 'run-history.json')),
  clipboard: new PolicyClipboardHistory(new EncryptedJsonClipboardStore(join(dataDirectory, 'clipboard.json'), encryptionKey), {
    enabled: true,
    maxItems: 200,
    retentionDays: 30,
    excludedAppIds: [],
    ignoreSensitive: true,
  }),
});

const backend = {
  searchCommands: async (query: string) => service.searchCommands(query),
  executeCommand: async (commandId: string) => service.executeCommand(commandId),
  listClipboard: async (query: string) => service.listClipboard(query),
  copyClipboard: async (itemId: string) => service.copyClipboard(itemId),
  captureClipboard: async (item: Parameters<PaletteService['captureClipboard']>[0]) => service.captureClipboard(item),
};

const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of input) {
  if (!line.trim()) continue;
  let response: BridgeResponse;
  try {
    response = await handleBridgeRequest(JSON.parse(line) as BridgeRequest, backend);
  } catch (error) {
    response = { id: 'invalid', ok: false, error: error instanceof Error ? error.message : String(error) };
  }
  process.stdout.write(`${JSON.stringify(response)}\n`);
}
