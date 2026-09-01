import { readdir, readFile } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import type { CommandDefinition, ProcessRunner } from './contracts.ts';
import type { ConfiguredCommand } from './command-config.ts';
import { defineProcessCommand } from './process-command.ts';

type ExtensionManifest = {
  id: string;
  name: string;
  commands: ConfiguredCommand[];
};

function commandPath(extensionDirectory: string, command: string): string {
  return command.startsWith('.') && !isAbsolute(command)
    ? resolve(extensionDirectory, command)
    : command;
}

/** Loads deliberately small, local-only process extensions from extension.json manifests. */
export async function loadLocalExtensions(
  extensionsDirectory: string,
  runner: ProcessRunner,
): Promise<CommandDefinition[]> {
  let directories;
  try {
    directories = await readdir(extensionsDirectory, { withFileTypes: true });
  } catch {
    return [];
  }

  const results: CommandDefinition[] = [];
  for (const directory of directories) {
    if (!directory.isDirectory() || directory.name.startsWith('.')) continue;
    const root = join(extensionsDirectory, directory.name);
    let manifest: Partial<ExtensionManifest>;
    try {
      manifest = JSON.parse(await readFile(join(root, 'extension.json'), 'utf8')) as Partial<ExtensionManifest>;
    } catch {
      continue;
    }
    if (typeof manifest.id !== 'string' || typeof manifest.name !== 'string' || !Array.isArray(manifest.commands)) continue;

    for (const candidate of manifest.commands) {
      if (!candidate || typeof candidate !== 'object') continue;
      if (typeof candidate.id !== 'string' || typeof candidate.title !== 'string' || typeof candidate.command !== 'string') continue;
      const command = defineProcessCommand({
        id: `extension:${manifest.id}:${candidate.id}`,
        title: candidate.title,
        subtitle: candidate.subtitle ?? manifest.name,
        keywords: [...(candidate.keywords ?? []), manifest.id, manifest.name],
        shortcut: candidate.shortcut,
        mode: candidate.mode,
        background: candidate.background,
        command: commandPath(root, candidate.command),
        args: candidate.args,
        cwd: candidate.cwd ? resolve(root, candidate.cwd) : root,
      }, runner);
      results.push({ ...command, category: 'extension' });
    }
  }
  return results;
}
