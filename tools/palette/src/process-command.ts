import type { CommandDefinition, InvocationMode, ProcessRunner } from './contracts.ts';

export type ProcessCommandOptions = {
  id: string;
  title: string;
  subtitle?: string;
  keywords?: string[];
  shortcut?: CommandDefinition['shortcut'];
  command: string;
  args?: string[];
  cwd?: string;
  mode?: InvocationMode;
  background?: boolean;
};

/** Creates a silent command without coupling command metadata to Node or a host. */
export function defineProcessCommand(
  options: ProcessCommandOptions,
  runner: ProcessRunner,
): CommandDefinition {
  return {
    id: options.id,
    title: options.title,
    subtitle: options.subtitle,
    keywords: options.keywords,
    shortcut: options.shortcut,
    mode: options.mode ?? 'silent',
    background: options.background ?? true,
    run: () => runner.run({
      command: options.command,
      args: options.args,
      cwd: options.cwd,
      background: options.background ?? true,
    }),
  };
}
