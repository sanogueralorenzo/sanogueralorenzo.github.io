import type {
  CommandContext,
  CommandDefinition,
  CommandResult,
  CommandSummary,
} from './contracts.ts';

function normalize(value: string): string {
  return value.trim().toLocaleLowerCase();
}

function score(command: CommandSummary, query: string): number {
  const needle = normalize(query);
  if (!needle) return 0;

  const title = normalize(command.title);
  const id = normalize(command.id);
  const keywords = (command.keywords ?? []).map(normalize);
  if (title === needle) return 100;
  if (title.startsWith(needle)) return 80;
  if (keywords.some((keyword) => keyword === needle)) return 70;
  if (title.includes(needle)) return 50;
  if (id.includes(needle) || keywords.some((keyword) => keyword.includes(needle))) return 30;
  return -1;
}

/** In-process command catalog shared by the launcher and native hosts. */
export class CommandRegistry {
  private readonly commands = new Map<string, CommandDefinition>();

  register(command: CommandDefinition): void {
    if (!command.id.trim()) throw new Error('Command id is required');
    if (this.commands.has(command.id)) {
      throw new Error(`Command already registered: ${command.id}`);
    }
    this.commands.set(command.id, command);
  }

  unregister(id: string): boolean {
    return this.commands.delete(id);
  }

  summaries(query = ''): CommandSummary[] {
    return [...this.commands.values()]
      .map(({ run: _run, ...summary }) => ({ summary, rank: score(summary, query) }))
      .filter(({ rank }) => !query.trim() || rank >= 0)
      .sort((a, b) => b.rank - a.rank || a.summary.title.localeCompare(b.summary.title))
      .map(({ summary }) => summary);
  }

  async execute(id: string, context: CommandContext): Promise<CommandResult> {
    const command = this.commands.get(id);
    if (!command) return { status: 'failure', message: `Unknown command: ${id}` };

    try {
      return await command.run({ ...context, invocation: command.mode });
    } catch (error) {
      return {
        status: 'failure',
        message: error instanceof Error ? error.message : String(error),
      };
    }
  }
}
