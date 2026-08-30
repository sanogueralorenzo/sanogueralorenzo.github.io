import { readFile } from 'node:fs/promises';
import type { CommandDefinition, Shortcut, ProcessRunner } from './contracts.ts';
import { defineProcessCommand } from './process-command.ts';

export type ConfiguredCommand = {
  id: string;
  title: string;
  subtitle?: string;
  keywords?: string[];
  shortcut?: Shortcut;
  mode?: 'visible' | 'silent';
  background?: boolean;
  command: string;
  args?: string[];
  cwd?: string;
};

export async function loadConfiguredCommands(path: string, runner: ProcessRunner): Promise<CommandDefinition[]> {
  let parsed: unknown;
  try { parsed = JSON.parse(await readFile(path, 'utf8')); } catch { return []; }
  if (!Array.isArray(parsed)) return [];
  return parsed.flatMap((value): CommandDefinition[] => {
    if (!value || typeof value !== 'object') return [];
    const command = value as Partial<ConfiguredCommand>;
    if (typeof command.id !== 'string' || typeof command.title !== 'string' || typeof command.command !== 'string') return [];
    return [defineProcessCommand({
      id: command.id,
      title: command.title,
      subtitle: command.subtitle,
      keywords: command.keywords,
      shortcut: command.shortcut,
      mode: command.mode,
      background: command.background,
      command: command.command,
      args: command.args,
      cwd: command.cwd,
    }, runner)];
  });
}
