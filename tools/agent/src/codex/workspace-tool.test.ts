import { mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { temporary } from "../test-support.js";
import { openFolder } from "./workspace-tool.js";

describe("open_folder", () => {
  it("selects an existing local folder", () => {
    const root = temporary("agent-folders-");
    const privateHome = join(root, ".agent");
    const project = join(root, "project");
    mkdirSync(privateHome);
    mkdirSync(project);
    expect(openFolder(project, privateHome)).toMatchObject({ cwd: realpathSync(project), result: { success: true } });
  });

  it("rejects missing, non-folder, and broad or private targets", () => {
    const root = temporary("agent-folders-");
    const privateHome = join(root, ".agent");
    const file = join(root, "file.txt");
    mkdirSync(privateHome);
    writeFileSync(file, "test");
    for (const path of ["project", join(root, "missing"), file, "/", homedir(), privateHome]) {
      expect(openFolder(path, privateHome).result.success).toBe(false);
    }
  });
});
