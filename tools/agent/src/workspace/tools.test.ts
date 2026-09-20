import { existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { Store } from "../conversation/store.js";
import { createTools } from "./tools.js";

const paths: string[] = [];

afterEach(() => {
  delete process.env.AGENT_TEST_SECRET;
  for (const path of paths.splice(0)) rmSync(path, { recursive: true, force: true });
});

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "agent-tools-"));
  const state = mkdtempSync(join(tmpdir(), "agent-tools-state-"));
  paths.push(root, state);
  const store = new Store(state);
  const tools = createTools(store, { allowCodeTools: true });
  const context = { cwd: root, sessionId: "test", memoryScope: "test" };
  return { root, store, tools, context };
}

describe("coding tool boundaries", () => {
  it("can expose project inspection without exposing mutation", () => {
    const root = mkdtempSync(join(tmpdir(), "agent-tools-readonly-"));
    const state = mkdtempSync(join(tmpdir(), "agent-tools-readonly-state-"));
    paths.push(root, state);
    const store = new Store(state);
    const names = createTools(store, { allowCodeTools: true, allowCodeWrites: false })
      .map((tool) => tool.definition.name);

    expect(names).toEqual(["memory_search", "remember", "read_file", "list_files", "search_files"]);
    store.close();
  });

  it("rejects writes outside the active project before creating directories", async () => {
    const { root, store, tools, context } = fixture();
    const outsideName = `${basename(root)}-escape`;
    const outside = join(dirname(root), outsideName);
    const tool = tools.find((candidate) => candidate.definition.name === "write_file")!;

    await expect(tool.execute({ path: `../${outsideName}/file.txt`, content: "no" }, context)).rejects.toThrow("outside");
    expect(existsSync(outside)).toBe(false);
    store.close();
  });

  it("does not expose secret-bearing environment variables to shell commands", async () => {
    const { store, tools, context } = fixture();
    process.env.AGENT_TEST_SECRET = "should-not-leak";
    writeFileSync(join(context.cwd, "show-env.mjs"), "process.stdout.write(process.env.AGENT_TEST_SECRET || 'clean')");
    const tool = tools.find((candidate) => candidate.definition.name === "run_command")!;
    const result = await tool.execute({ program: "node", args: ["show-env.mjs"] }, context);

    expect(result.output).toBe("clean");
    store.close();
  });

  it("does not follow a file symlink outside the active project", async () => {
    const { root, store, tools, context } = fixture();
    const outside = join(dirname(root), `${basename(root)}-outside.txt`);
    paths.push(outside);
    writeFileSync(outside, "safe");
    symlinkSync(outside, join(root, "link.txt"));
    const tool = tools.find((candidate) => candidate.definition.name === "write_file")!;

    await expect(tool.execute({ path: "link.txt", content: "changed" }, context)).rejects.toThrow("outside");
    expect(readFileSync(outside, "utf8")).toBe("safe");
    store.close();
  });

  it("does not create through an outside directory symlink", async () => {
    const { root, store, tools, context } = fixture();
    const outside = mkdtempSync(join(tmpdir(), "agent-outside-"));
    paths.push(outside);
    symlinkSync(outside, join(root, "linked-directory"));
    const tool = tools.find((candidate) => candidate.definition.name === "write_file")!;

    await expect(tool.execute({ path: "linked-directory/new/file.txt", content: "changed" }, context)).rejects.toThrow("outside");
    expect(existsSync(join(outside, "new"))).toBe(false);
    store.close();
  });
});
