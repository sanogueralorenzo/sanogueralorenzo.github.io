import type {
  CommandContext,
  CommandResult,
  MenubarHost,
  RunHistoryEntry,
  RunHistoryStore,
} from './contracts.ts';
import { CommandRegistry } from './command-registry.ts';

function idForRun(commandId: string, startedAt: number): string {
  return `${commandId}:${startedAt}:${Math.random().toString(36).slice(2, 8)}`;
}

/** Executes commands from shortcuts, the launcher, and the menubar uniformly. */
export class CommandDispatcher {
  private readonly registry: CommandRegistry;
  private readonly host: Pick<MenubarHost, 'notify' | 'setMenubarIcon'>;
  private readonly history: RunHistoryStore;
  private readonly context: Omit<CommandContext, 'invocation'>;

  constructor(
    registry: CommandRegistry,
    host: Pick<MenubarHost, 'notify' | 'setMenubarIcon'>,
    history: RunHistoryStore,
    context: Omit<CommandContext, 'invocation'>,
  ) {
    this.registry = registry;
    this.host = host;
    this.history = history;
    this.context = context;
  }

  async execute(commandId: string): Promise<CommandResult> {
    const startedAt = Date.now();
    await this.host.setMenubarIcon('working');
    const result = await this.registry.execute(commandId, {
      ...this.context,
      invocation: this.registry.modeOf(commandId) ?? 'visible',
    });
    const finishedAt = Date.now();
    const entry: RunHistoryEntry = { id: idForRun(commandId, startedAt), commandId, startedAt, finishedAt, result };
    await this.history.append(entry);

    if (result.status === 'failure') {
      await this.host.setMenubarIcon('error');
    } else {
      await this.host.setMenubarIcon('ready');
    }

    if (this.registry.modeOf(commandId) === 'silent') {
      await this.host.notify({
        title: result.status === 'success' ? 'Action completed' : 'Action failed',
        body: result.message ?? result.output,
        level: result.status === 'success' ? 'success' : 'error',
      });
    }
    return result;
  }
}
