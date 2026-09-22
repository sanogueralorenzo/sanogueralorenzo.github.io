import type { RunEnvelope, RuntimeSnapshot } from "../conversation/types.js";

export const ansi = {
  dim: (text: string) => process.stdout.isTTY ? `\u001b[2m${text}\u001b[22m` : text,
  cyan: (text: string) => process.stdout.isTTY ? `\u001b[36m${text}\u001b[39m` : text,
  red: (text: string) => process.stdout.isTTY ? `\u001b[31m${text}\u001b[39m` : text,
};

export class CliOutput {
  activeRunId: string | undefined;
  private activeOutput = "";
  private activeArtifacts = new Set<string>();
  private wroteText = false;
  private completed = new Set<string>();
  private waiters = new Map<string, () => void>();
  private latestSnapshot: RuntimeSnapshot | undefined;
  private seenReports = new Map<string, string>();

  constructor(
    public sessionId: string,
    private readonly status: (message: string) => void,
    private readonly changeSession: (id: string) => void,
    private readonly promptActive: () => boolean,
  ) {}

  submitted(runId: string): void {
    if (this.completed.has(runId)) return;
    const alreadyObserving = this.activeRunId === runId;
    this.activeRunId = runId;
    if (!alreadyObserving && (this.latestSnapshot?.activeRuns.some((active) => active.run.id === runId)
      || this.latestSnapshot?.lastRuns.some((last) => last.id === runId))) {
      this.restore(this.latestSnapshot);
    }
  }

  waitFor(runId: string): Promise<void> {
    if (this.completed.delete(runId)) return Promise.resolve();
    return new Promise<void>((resolve) => this.waiters.set(runId, resolve));
  }

  release(runId: string): void {
    if (this.activeRunId === runId) this.activeRunId = undefined;
  }

  resolveWaiters(): void {
    for (const resolve of this.waiters.values()) resolve();
    this.waiters.clear();
  }

  private finish(runId: string): void {
    const waiter = this.waiters.get(runId);
    if (waiter) {
      this.waiters.delete(runId);
      waiter();
    } else {
      this.completed.add(runId);
      if (this.completed.size > 32) this.completed.delete(this.completed.values().next().value!);
    }
  }

  private endRun(runId: string): void {
    this.activeRunId = undefined;
    this.activeOutput = "";
    this.activeArtifacts.clear();
    this.wroteText = false;
    this.finish(runId);
  }

  private restore(snapshot: RuntimeSnapshot): void {
    const first = this.latestSnapshot === undefined;
    this.latestSnapshot = snapshot;
    for (const report of first ? snapshot.taskReports.slice(0, 5) : snapshot.taskReports) {
      if (!first && this.seenReports.get(report.sessionId) === report.updatedAt) continue;
      this.status(`${report.title} · ${report.summary} ${report.url}`);
    }
    this.seenReports = new Map(snapshot.taskReports.map((report) => [report.sessionId, report.updatedAt]));
    const active = snapshot.activeRuns.find((run) => run.run.sessionId === this.sessionId);
    const lastRun = snapshot.lastRuns.find((run) => run.sessionId === this.sessionId);
    if (!active) {
      if (this.activeRunId) {
        const saved = lastRun?.id === this.activeRunId
          ? snapshot.transcript?.messages.at(-1)
          : null;
        if (saved?.role === "assistant" && saved.content.startsWith(this.activeOutput)) {
          process.stdout.write(saved.content.slice(this.activeOutput.length));
          if (saved.content.length > this.activeOutput.length) process.stdout.write("\n");
        } else this.status("Response ended while reconnecting. You can try again.");
        this.endRun(this.activeRunId);
      }
      return;
    }
    if (this.activeRunId && this.activeRunId !== active.run.id) this.finish(this.activeRunId);
    if (this.activeRunId !== active.run.id) this.render({ sessionId: this.sessionId, runId: active.run.id, event: active.turn });
    if (active.navigation && this.sessionId !== active.navigation.session.id) {
      this.status(`Opened “${active.navigation.session.title}”.`);
      this.changeSession(active.navigation.session.id);
    }
    const missing = active.output.startsWith(this.activeOutput) ? active.output.slice(this.activeOutput.length) : `\n${active.output}`;
    if (missing) process.stdout.write(missing);
    this.activeOutput = active.output;
    this.wroteText = Boolean(active.output);
    for (const artifact of active.artifacts) {
      if (this.activeArtifacts.has(artifact.id)) continue;
      process.stdout.write(`${this.wroteText ? "\n" : ""}${ansi.dim(`· ${artifact.name}`)} ${artifact.path}\n`);
      this.activeArtifacts.add(artifact.id);
      this.wroteText = false;
    }
  }

  render({ runId, event }: RunEnvelope): void {
    if (event.type === "snapshot") {
      this.restore(event.snapshot);
      return;
    }
    if (event.type === "navigate") {
      this.status(`Opened “${event.session.title}”.`);
      if (event.continues) this.activeRunId = runId;
      if (!event.continues && this.activeRunId === runId) {
        this.activeRunId = undefined;
        this.finish(runId);
      }
      this.changeSession(event.session.id);
      return;
    }
    if (event.type === "task_report") {
      if (this.seenReports.get(event.report.sessionId) === event.report.updatedAt) return;
      this.seenReports.set(event.report.sessionId, event.report.updatedAt);
      this.status(`${event.report.title} · ${event.report.summary} ${event.report.url}`);
      return;
    }
    if (event.type === "home_error") {
      this.status(event.message);
      return;
    }
    if (event.type === "turn") {
      this.activeRunId = runId;
      this.activeOutput = "";
      this.activeArtifacts = new Set();
      this.wroteText = false;
      if (event.channel !== "cli") {
        const input = event.text.trim() || (event.hasAttachments ? "Voice message" : "Message");
        process.stdout.write(`${this.promptActive() ? "\n" : ""}${ansi.cyan(event.channel)} › ${input}\n`);
      }
      return;
    }
    if (this.activeRunId !== runId) return;
    switch (event.type) {
      case "text_delta":
        process.stdout.write(event.delta);
        this.activeOutput += event.delta;
        this.wroteText = true;
        break;
      case "tool_start":
        process.stdout.write(`${this.wroteText ? "\n" : ""}${ansi.dim(`· ${event.name}`)}\n`);
        this.wroteText = false;
        break;
      case "status":
        process.stdout.write(`${this.wroteText ? "\n" : ""}${ansi.dim(`· ${event.message}`)}\n`);
        this.wroteText = false;
        break;
      case "artifact":
        process.stdout.write(`${this.wroteText ? "\n" : ""}${ansi.dim(`· ${event.artifact.name}`)} ${event.artifact.path}\n`);
        this.activeArtifacts.add(event.artifact.id);
        this.wroteText = false;
        break;
      case "error":
        process.stdout.write(`${this.wroteText ? "\n" : ""}${ansi.red(event.message)}\n`);
        this.endRun(runId);
        break;
      case "done":
        if (this.wroteText) process.stdout.write("\n");
        this.endRun(runId);
        break;
    }
  }
}
