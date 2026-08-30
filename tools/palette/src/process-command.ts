import type { CommandDefinition, ProcessRunner } from './contracts.ts';

export type ProcessCommandOptions = {
  id: string;
  title: string;
  subtitle?: string;
  keywords?: string[];
  shortcut?: CommandDefinition['shortcut'];
  command: string;
  args?: string[];
  cwd?: string;
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
    mode: 'silent',
    background: true,
    run: () => runner.run({
      command: options.command,
      args: options.args,
      cwd: options.cwd,
      background: true,
    }),
  };
}
