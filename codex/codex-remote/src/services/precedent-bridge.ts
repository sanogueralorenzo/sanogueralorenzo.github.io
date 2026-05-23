import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { join } from "node:path";
import type { TurnProgressEvent } from "../adapters/app-server/client.js";

export type PrecedentBridge = {
  beforeTurn: (input: PrecedentBeforeTurnInput) => Promise<PrecedentBeforeTurnResult>;
  beforeRetry: (input: PrecedentBeforeRetryInput) => Promise<PrecedentBeforeRetryResult>;
  observeTurnEvent: (input: PrecedentTurnEventInput) => Promise<void>;
  afterRetry: (input: PrecedentAfterRetryInput) => Promise<void>;
  afterTurn: (input: PrecedentAfterTurnInput) => Promise<void>;
};

export type PrecedentBeforeTurnInput = {
  cwd: string;
  threadId: string;
  task: string;
};

export type PrecedentBeforeTurnResult = {
  task: string;
  contextBlock: string;
  candidateHints: unknown[];
  promotionTrials: unknown[];
  attributedPrecedents: string[];
};

export type PrecedentBeforeRetryInput = {
  cwd: string;
  threadId: string;
  task: string;
  attributedPrecedents: string[];
};

export type PrecedentBeforeRetryResult = {
  repairBlock: string;
  repairId: string | null;
};

export type PrecedentAfterTurnInput = {
  cwd: string;
  threadId: string;
  task: string;
  success: boolean;
  response: string;
  attributedPrecedents: string[];
};

export type PrecedentAfterRetryInput = {
  cwd: string;
  threadId: string;
  repairId: string;
  attributedPrecedents: string[];
};

export type PrecedentTurnEventInput = {
  cwd: string;
  threadId: string;
  event: TurnProgressEvent;
  attributedPrecedents: string[];
};

type PrecedentBridgeConfig = {
  enabled: boolean;
  stateDir?: string;
  hookTimeoutMs?: number;
  contextTimeoutMs?: number;
};

type JsonRunner = (input: {
  cwd: string;
  args: string[];
  stdinJson?: unknown;
  timeoutMs?: number;
}) => Promise<unknown>;

const DEFAULT_HOOK_TIMEOUT_MS = 1500;
const DEFAULT_CONTEXT_TIMEOUT_MS = 2500;
const PROCESS_KILL_GRACE_MS = 250;
const MAX_PROCESS_OUTPUT_BYTES = 512 * 1024;

export function createPrecedentBridge(config: PrecedentBridgeConfig, runner: JsonRunner = runPrecedentJson): PrecedentBridge {
  if (!config.enabled) {
    return disabledPrecedentBridge();
  }

  const stateDir = config.stateDir ?? ".precedent";
  const hookTimeoutMs = positiveNumber(config.hookTimeoutMs) ?? DEFAULT_HOOK_TIMEOUT_MS;
  const contextTimeoutMs = positiveNumber(config.contextTimeoutMs) ?? DEFAULT_CONTEXT_TIMEOUT_MS;

  return {
    beforeTurn: async (input) => {
      try {
        const attach = await runWithTimeout(runner, {
          cwd: input.cwd,
          args: [
            "attach",
            "--runtime",
            "codex",
            "--state-dir",
            stateDir,
            "--thread-id",
            input.threadId,
            "--task",
            input.task,
            "--json",
          ],
          timeoutMs: contextTimeoutMs,
        }, contextTimeoutMs) as { adapter?: { beforeTurn?: { command?: string[] } } };
        const command = attach.adapter?.beforeTurn?.command;
        if (!Array.isArray(command) || command.length < 3) {
          return emptyBeforeTurn(input.task);
        }

        const context = await runWithTimeout(runner, {
          cwd: input.cwd,
          args: command.slice(2),
          timeoutMs: contextTimeoutMs,
        }, contextTimeoutMs) as {
          contextBlock?: string;
          candidateHints?: unknown[];
          promotionTrials?: unknown[];
          injections?: Array<{ id?: string }>;
        };
        const contextBlock = typeof context.contextBlock === "string" ? context.contextBlock : "";
        return {
          task: contextBlock ? `${contextBlock}\n\n${input.task}` : input.task,
          contextBlock,
          candidateHints: Array.isArray(context.candidateHints) ? context.candidateHints : [],
          promotionTrials: Array.isArray(context.promotionTrials) ? context.promotionTrials : [],
          attributedPrecedents: Array.isArray(context.injections)
            ? context.injections.map((injection) => injection.id).filter((id): id is string => typeof id === "string")
            : [],
        };
      } catch (error) {
        logPrecedentFailure("context.before_turn", input, error);
        return emptyBeforeTurn(input.task);
      }
    },
    beforeRetry: async (input) => {
      try {
        const result = await runWithTimeout(runner, {
          cwd: input.cwd,
          args: [
            "hook",
            "--state-dir",
            stateDir,
            "--json",
          ],
          stdinJson: {
            schema_version: "precedent.v1",
            hook: "repair.before_retry",
            sessionId: sessionIdForThread(input.cwd, input.threadId),
            nextSessionId: sessionIdForThread(input.cwd, input.threadId),
            task: input.task,
            attributedPrecedents: input.attributedPrecedents,
          },
          timeoutMs: contextTimeoutMs,
        }, contextTimeoutMs) as { repairBlock?: string; repairId?: string | null };
        const repairBlock = typeof result.repairBlock === "string" ? result.repairBlock : "";
        const repairId = typeof result.repairId === "string" && result.repairId.trim()
          ? result.repairId
          : null;
        return { repairBlock, repairId };
      } catch (error) {
        logPrecedentFailure("repair.before_retry", input, error);
        return emptyBeforeRetry();
      }
    },
    observeTurnEvent: async (input) => {
      try {
        const payload = turnEventHookPayload(input);
        if (!payload) {
          return;
        }
        await runWithTimeout(runner, {
          cwd: input.cwd,
          args: [
            "hook",
            "--state-dir",
            stateDir,
            "--json",
          ],
          stdinJson: payload,
          timeoutMs: hookTimeoutMs,
        }, hookTimeoutMs);
      } catch (error) {
        logPrecedentFailure("turn_event", input, error);
        // Precedent is advisory; runtime turns must fail open.
      }
    },
    afterRetry: async (input) => {
      try {
        await runWithTimeout(runner, {
          cwd: input.cwd,
          args: [
            "hook",
            "--state-dir",
            stateDir,
            "--json",
          ],
          stdinJson: {
            schema_version: "precedent.v1",
            hook: "repair.after_retry",
            sessionId: sessionIdForThread(input.cwd, input.threadId),
            repairId: input.repairId,
            repairSessionId: sessionIdForThread(input.cwd, input.threadId),
            attributedPrecedents: input.attributedPrecedents,
          },
          timeoutMs: hookTimeoutMs,
        }, hookTimeoutMs);
      } catch (error) {
        logPrecedentFailure("repair.after_retry", input, error);
        // Precedent is advisory; runtime turns must fail open.
      }
    },
    afterTurn: async (input) => {
      try {
        await runWithTimeout(runner, {
          cwd: input.cwd,
          args: [
            "hook",
            "--state-dir",
            stateDir,
            "--json",
          ],
          stdinJson: {
            schema_version: "precedent.v1",
            hook: "outcome.after_task",
            sessionId: sessionIdForThread(input.cwd, input.threadId),
            success: input.success,
            status: input.success ? "success" : "failure",
            task: input.task,
            notes: input.response,
            attributedPrecedents: input.attributedPrecedents,
          },
          timeoutMs: hookTimeoutMs,
        }, hookTimeoutMs);
      } catch (error) {
        logPrecedentFailure("outcome.after_task", input, error);
        // Precedent is advisory; runtime turns must fail open.
      }
    },
  };
}

export function precedentBridgeConfigFromEnv(env: NodeJS.ProcessEnv): PrecedentBridgeConfig {
  return {
    enabled: env.PRECEDENT_ENABLED === "1" || env.PRECEDENT_ENABLED === "true",
    stateDir: env.PRECEDENT_STATE_DIR,
    hookTimeoutMs: parsePositiveInteger(env.PRECEDENT_HOOK_TIMEOUT_MS),
    contextTimeoutMs: parsePositiveInteger(env.PRECEDENT_CONTEXT_TIMEOUT_MS),
  };
}

function disabledPrecedentBridge(): PrecedentBridge {
  return {
    beforeTurn: async (input) => emptyBeforeTurn(input.task),
    beforeRetry: async () => emptyBeforeRetry(),
    observeTurnEvent: async () => {},
    afterRetry: async () => {},
    afterTurn: async () => {},
  };
}

function emptyBeforeTurn(task: string): PrecedentBeforeTurnResult {
  return {
    task,
    contextBlock: "",
    candidateHints: [],
    promotionTrials: [],
    attributedPrecedents: [],
  };
}

function emptyBeforeRetry(): PrecedentBeforeRetryResult {
  return {
    repairBlock: "",
    repairId: null,
  };
}

function sessionIdForThread(cwd: string, threadId: string): string {
  return `session_${stableHash({
    runtime: "codex",
    cwd,
    threadId,
  }).slice(0, 16)}`;
}

function turnEventHookPayload(input: PrecedentTurnEventInput): unknown | null {
  const sessionId = sessionIdForThread(input.cwd, input.threadId);

  if (input.event.kind === "itemCompleted" && input.event.itemType === "commandExecution") {
    if (!input.event.command || input.event.exitCode === null) {
      return null;
    }

    return {
      schema_version: "precedent.v1",
      hook: "validation.after_run",
      sessionId,
      command: input.event.command,
      exitCode: input.event.exitCode,
      durationMs: input.event.durationMs,
      stdout: input.event.output ?? "",
      stderr: "",
      attributedPrecedents: input.attributedPrecedents,
    };
  }

  if (input.event.kind === "turnDiffUpdated" && input.event.diff.trim()) {
    return {
      schema_version: "precedent.v1",
      hook: "diff.after_edit",
      sessionId,
      unifiedDiff: input.event.diff,
      attributedPrecedents: input.attributedPrecedents,
    };
  }

  return null;
}

async function runWithTimeout(runner: JsonRunner, input: Parameters<JsonRunner>[0], timeoutMs: number): Promise<unknown> {
  let timeout: ReturnType<typeof setTimeout> | null = null;
  try {
    return await Promise.race([
      runner(input),
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => {
          reject(new PrecedentTimeoutError(timeoutMs));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
}

async function runPrecedentJson(input: { cwd: string; args: string[]; stdinJson?: unknown; timeoutMs?: number }): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let settled = false;
    let timedOut = false;
    let killTimer: ReturnType<typeof setTimeout> | null = null;
    let timeout: ReturnType<typeof setTimeout> | null = null;
    const child = spawn(process.execPath, [join(input.cwd, "precedent/bin/precedent.mjs"), ...input.args], {
      cwd: input.cwd,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout = appendBounded(stdout, chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr = appendBounded(stderr, chunk);
    });
    child.on("error", (error) => {
      rejectOnce(error);
    });
    child.on("close", (exitCode) => {
      if (timedOut) {
        return;
      }
      clearTimers();
      if (exitCode !== 0) {
        rejectOnce(new Error(stderr || `precedent exited ${exitCode}`));
        return;
      }

      try {
        resolveOnce(JSON.parse(stdout));
      } catch (error) {
        rejectOnce(error);
      }
    });

    if (input.timeoutMs && input.timeoutMs > 0) {
      timeout = setTimeout(() => {
        timedOut = true;
        child.kill("SIGTERM");
        killTimer = setTimeout(() => {
          if (child.exitCode === null && child.signalCode === null) {
            child.kill("SIGKILL");
          }
        }, PROCESS_KILL_GRACE_MS);
        rejectOnce(new PrecedentTimeoutError(input.timeoutMs ?? 0));
      }, input.timeoutMs);
    }

    if (input.stdinJson) {
      child.stdin.end(`${JSON.stringify(input.stdinJson)}\n`);
    } else {
      child.stdin.end();
    }

    function resolveOnce(value: unknown): void {
      if (settled) {
        return;
      }
      settled = true;
      clearTimers();
      resolve(value);
    }

    function rejectOnce(error: unknown): void {
      if (settled) {
        return;
      }
      settled = true;
      clearTimers();
      reject(error);
    }

    function clearTimers(): void {
      if (timeout) {
        clearTimeout(timeout);
        timeout = null;
      }
      if (killTimer) {
        clearTimeout(killTimer);
        killTimer = null;
      }
    }
  });
}

class PrecedentTimeoutError extends Error {
  constructor(timeoutMs: number) {
    super(`precedent timed out after ${timeoutMs}ms`);
    this.name = "PrecedentTimeoutError";
  }
}

function appendBounded(current: string, chunk: string): string {
  const next = current + chunk;
  if (Buffer.byteLength(next, "utf8") <= MAX_PROCESS_OUTPUT_BYTES) {
    return next;
  }
  return next.slice(-MAX_PROCESS_OUTPUT_BYTES);
}

function parsePositiveInteger(value: string | undefined): number | undefined {
  if (!value) {
    return undefined;
  }

  const parsed = Number.parseInt(value, 10);
  return positiveNumber(parsed);
}

function positiveNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.floor(value)
    : undefined;
}

function logPrecedentFailure(hook: string, input: { cwd: string; threadId: string }, error: unknown): void {
  const message = error instanceof Error ? error.message : String(error);
  console.warn(JSON.stringify({
    level: "warn",
    service: "codex-remote",
    component: "precedent",
    hook,
    threadId: input.threadId,
    sessionId: sessionIdForThread(input.cwd, input.threadId),
    message,
  }));
}

function stableHash(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(sortObject(value))).digest("hex");
}

function sortObject(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sortObject);
  }

  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, item]) => [key, sortObject(item)])
    );
  }

  return value;
}
