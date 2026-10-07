import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { createReadOnlyTools } from "@earendil-works/pi-coding-agent";
import { agentResources } from "./agent-resources.ts";

test("researcher configuration discovers project instructions and skills while native search finds evidence", async () => {
  const cwd = mkdtempSync(join(tmpdir(), "assistant-resource-test-"));
  try {
    writeFileSync(join(cwd, "AGENTS.md"), "Respect the project's release boundary.");
    mkdirSync(join(cwd, "src"));
    writeFileSync(join(cwd, "src", "cache.ts"), "export const ttlMs = 90000;\n");
    mkdirSync(join(cwd, ".pi", "skills", "ownership"), { recursive: true });
    writeFileSync(join(cwd, ".pi", "skills", "ownership", "SKILL.md"), "---\nname: ownership\ndescription: Resolve service owners.\n---\nRead the owner evidence.");
    const researcher = agentResources(cwd, "researcher");
    await researcher.reload();
    assert.ok(researcher.getAgentsFiles().agentsFiles.some(f => f.content.includes("release boundary")));
    assert.ok(researcher.getSkills().skills.some(s => s.name === "ownership"));
    const native = createReadOnlyTools(cwd);
    for (const [name, args, expected] of [["find", { pattern: "**/*.ts", path: "." }, "cache.ts"], ["grep", { pattern: "ttlMs", path: "." }, "90000"]] as const) {
      const tool = native.find(t => t.name === name)!;
      const result = await tool.execute("test", args);
      assert.ok(result.content.some(p => p.type === "text" && p.text.includes(expected)), `${name} must find the workspace source`);
    }
    const coordinator = agentResources(cwd, "coordinator");
    await coordinator.reload();
    assert.equal(coordinator.getSkills().skills.length, 0);
    assert.equal(coordinator.getAgentsFiles().agentsFiles.length, 0);
    assert.deepEqual(native.map(tool => tool.name), ["read", "grep", "find", "ls"]);
  } finally { rmSync(cwd, { recursive: true, force: true }); }
});
