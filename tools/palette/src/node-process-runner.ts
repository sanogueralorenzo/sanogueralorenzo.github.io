import { spawn, type ChildProcessByStdio } from 'node:child_process';
import type { Readable } from 'node:stream';
import type { ProcessRunner, CommandResult } from './contracts.ts';

/**
 * Node service adapter for silent commands.
 *
 * Arguments are passed directly to `spawn` with no shell interpolation. This
 * keeps background actions predictable and avoids turning command shortcuts
 * into an accidental shell-injection surface.
 */
export class NodeProcessRunner implements ProcessRunner {
  async run(spec: {
    command: string;
    args?: string[];
    cwd?: string;
    background?: boolean;
    signal?: AbortSignal;
  }): Promise<CommandResult> {
    return new Promise((resolve) => {
      let settled = false;
      let stdout = '';
      let stderr = '';
      let child: ChildProcessByStdio<null, Readable, Readable>;

      const finish = (result: CommandResult): void => {
        if (settled) return;
        settled = true;
        resolve(result);
      };

      try {
        child = spawn(spec.command, spec.args ?? [], {
          cwd: spec.cwd,
          shell: false,
          stdio: ['ignore', 'pipe', 'pipe'],
          windowsHide: true,
        });
      } catch (error) {
        finish({ status: 'failure', message: error instanceof Error ? error.message : String(error) });
        return;
      }

      child.stdout.on('data', (chunk: Buffer | string) => { stdout += chunk.toString(); });
      child.stderr.on('data', (chunk: Buffer | string) => { stderr += chunk.toString(); });
      child.once('error', (error) => {
        finish({ status: 'failure', message: error.message, output: stderr || stdout });
      });
      child.once('close', (exitCode) => {
        const output = stdout || stderr || undefined;
        finish(exitCode === 0
          ? { status: 'success', output, exitCode: 0 }
          : { status: 'failure', message: stderr.trim() || `Process exited with code ${exitCode ?? 'unknown'}`, output, exitCode: exitCode ?? undefined });
      });

      if (spec.signal) {
        const abort = (): void => {
          if (!settled) child.kill();
        };
        if (spec.signal.aborted) abort();
        else spec.signal.addEventListener('abort', abort, { once: true });
      }
    });
  }
}
