/**
 * Platform-neutral contracts for Palette.
 *
 * These types deliberately contain no Electron, browser, or operating-system
 * imports. Native hosts and the web UI can depend on them without depending on
 * one another.
 */

export type Platform = 'macos' | 'windows' | 'linux';
export type InvocationMode = 'visible' | 'silent';

export type Shortcut =
  | { kind: 'accelerator'; value: string }
  | { kind: 'chord'; steps: string[]; timeoutMs?: number };

export type CommandResult = {
  status: 'success' | 'failure';
  message?: string;
  output?: string;
  exitCode?: number;
  nextView?: 'clipboard' | 'history';
};

export type CommandContext = {
  platform: Platform;
  invocation: InvocationMode;
  query?: string;
  signal: AbortSignal;
};

export type CommandDefinition = {
  id: string;
  title: string;
  subtitle?: string;
  keywords?: string[];
  mode: InvocationMode;
  shortcut?: Shortcut;
  /** A command that starts a process without requiring a visible terminal. */
  background?: boolean;
  category?: 'command' | 'app' | 'file' | 'extension';
  run: (context: CommandContext) => Promise<CommandResult>;
};

export type CommandSummary = Omit<CommandDefinition, 'run'>;

export type Notification = {
  title: string;
  body?: string;
  level?: 'info' | 'success' | 'error';
};

export type MenubarIconState = 'ready' | 'working' | 'error';

export type MenubarMenuItem =
  | { kind: 'command'; id: string; title: string; shortcut?: Shortcut }
  | { kind: 'separator' }
  | { kind: 'action'; id: string; title: string };

export interface PlatformHost {
  readonly platform: Platform;
  showLauncher(query?: string): Promise<void>;
  hideLauncher(): Promise<void>;
  registerShortcut(shortcut: Shortcut, callback: () => void): Promise<void>;
  unregisterShortcut(shortcut: Shortcut): Promise<void>;
  notify(notification: Notification): Promise<void>;
  writeClipboard(content: string): Promise<void>;
  openPath(path: string): Promise<void>;
}

export interface MenubarHost extends PlatformHost {
  setMenubarIcon(state: MenubarIconState): Promise<void>;
  setMenubarMenu(items: MenubarMenuItem[]): Promise<void>;
}

export type RunHistoryEntry = {
  id: string;
  commandId: string;
  startedAt: number;
  finishedAt: number;
  result: CommandResult;
};

export interface RunHistoryStore {
  append(entry: RunHistoryEntry): Promise<void>;
  list(limit?: number): Promise<RunHistoryEntry[]>;
}

export type ClipboardKind = 'text' | 'url' | 'image' | 'file';

export type ClipboardItem = {
  id: string;
  kind: ClipboardKind;
  content: string;
  sourceAppId?: string;
  createdAt: number;
  pinned: boolean;
};

export type ClipboardCapture = ClipboardItem & { sensitive?: boolean };

export type ClipboardPolicy = {
  enabled: boolean;
  maxItems: number;
  retentionDays: number | null;
  excludedAppIds: string[];
  /** Applications or content classifiers may mark a copy as sensitive. */
  ignoreSensitive: boolean;
};

export interface ClipboardStore {
  list(query?: string): Promise<ClipboardItem[]>;
  add(item: ClipboardItem): Promise<boolean>;
  remove(id: string): Promise<boolean>;
  setPinned(id: string, pinned: boolean): Promise<ClipboardItem | null>;
  clear(): Promise<void>;
}

export interface ProcessRunner {
  run(spec: {
    command: string;
    args?: string[];
    cwd?: string;
    background?: boolean;
    signal?: AbortSignal;
  }): Promise<CommandResult>;
}
