package main

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestCodexHookConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installCodexHooks(repo); err != nil {
		t.Fatalf("installCodexHooks: %v", err)
	}
	var file hookFile
	readTestJSON(t, filepath.Join(repo, ".codex", "hooks.json"), &file)
	for _, event := range []string{"SessionStart", "SessionEnd", "UserPromptSubmit", "Stop"} {
		if len(file.Hooks[event]) == 0 {
			t.Fatalf("missing Codex event %s", event)
		}
	}
	if len(file.Hooks["PostToolUse"]) != 0 {
		t.Fatalf("unexpected Codex tool hook: %#v", file.Hooks["PostToolUse"])
	}
	assertContainsFile(t, filepath.Join(repo, ".codex", "hooks.json"), "trace ingest codex turn-start")
	assertContainsFile(t, filepath.Join(repo, ".codex", "hooks.json"), `"timeout": 3`)
	assertContainsFile(t, filepath.Join(repo, ".codex", "config.toml"), "codex_hooks = true")
}

func TestClaudeHookConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installClaudeHooks(repo); err != nil {
		t.Fatalf("installClaudeHooks: %v", err)
	}
	var settings claudeSettings
	readTestJSON(t, filepath.Join(repo, ".claude", "settings.json"), &settings)
	for _, event := range []string{"SessionStart", "SessionEnd", "UserPromptSubmit", "Stop"} {
		if len(settings.Hooks[event]) == 0 {
			t.Fatalf("missing Claude event %s", event)
		}
	}
	if len(settings.Hooks["PreToolUse"]) != 0 || len(settings.Hooks["PostToolUse"]) != 0 {
		t.Fatalf("unexpected Claude tool hooks: %#v", settings.Hooks)
	}
	assertContainsFile(t, filepath.Join(repo, ".claude", "settings.json"), "trace ingest claude-code turn-start")
}

func TestCodexTraceOwnedHooksAreReplaced(t *testing.T) {
	repo := testRepo(t)
	writeFile(t, filepath.Join(repo, ".codex", "hooks.json"), `{"hooks":{"Stop":[{"matcher":null,"hooks":[{"type":"command","command":"trace hooks codex old-stop","timeout":30},{"type":"command","command":"custom hook"}]}],"PostToolUse":[{"matcher":null,"hooks":[{"type":"command","command":"trace hooks codex post-tool-use","timeout":30}]}]}}`)
	if err := installCodexHooks(repo); err != nil {
		t.Fatalf("installCodexHooks: %v", err)
	}
	got := readFile(t, filepath.Join(repo, ".codex", "hooks.json"))
	if strings.Contains(got, "old-stop") || strings.Contains(got, "post-tool-use") {
		t.Fatalf("old Trace hook was not replaced: %s", got)
	}
	if !strings.Contains(got, "custom hook") || !strings.Contains(got, "trace ingest codex turn-end") {
		t.Fatalf("expected custom hook preserved and new Trace hook installed: %s", got)
	}
}

func TestClaudeTraceOwnedHooksAreReplaced(t *testing.T) {
	repo := testRepo(t)
	writeFile(t, filepath.Join(repo, ".claude", "settings.json"), `{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"trace hooks claude-code old-stop"},{"type":"command","command":"custom hook"}]}],"PreToolUse":[{"matcher":"Task","hooks":[{"type":"command","command":"trace hooks claude-code pre-task"}]}]}}`)
	if err := installClaudeHooks(repo); err != nil {
		t.Fatalf("installClaudeHooks: %v", err)
	}
	got := readFile(t, filepath.Join(repo, ".claude", "settings.json"))
	if strings.Contains(got, "old-stop") || strings.Contains(got, "pre-task") {
		t.Fatalf("old Trace hook was not replaced: %s", got)
	}
	if !strings.Contains(got, "custom hook") || !strings.Contains(got, "trace ingest claude-code turn-end") {
		t.Fatalf("expected custom hook preserved and new Trace hook installed: %s", got)
	}
}

func TestOpenCodePluginConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installOpenCodePlugin(repo); err != nil {
		t.Fatalf("installOpenCodePlugin: %v", err)
	}
	path := filepath.Join(repo, ".opencode", "plugins", "trace.ts")
	assertContainsFile(t, path, `[TRACE_CMD, "ingest", "opencode", event]`)
	assertContainsFile(t, path, `case "message.updated"`)
	assertContainsFile(t, path, `resetSession(msg.sessionID)`)
	assertContainsFile(t, path, `spawnSync(cmd, args`)
}

func TestPiExtensionConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installPiExtension(repo); err != nil {
		t.Fatalf("installPiExtension: %v", err)
	}
	path := filepath.Join(repo, ".pi", "extensions", "trace", "index.ts")
	assertContainsFile(t, path, `from "@earendil-works/pi-coding-agent"`)
	assertContainsFile(t, path, `["ingest", "pi", event]`)
	assertContainsFile(t, path, "TRACE_PI_NESTED")
	assertContainsFile(t, path, `agent.on("before_agent_start"`)
	assertContainsFile(t, path, `agent.on("agent_end"`)
}

func TestOMPExtensionConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installOMPExtension(repo); err != nil {
		t.Fatalf("installOMPExtension: %v", err)
	}
	path := filepath.Join(repo, ".omp", "extensions", "trace", "index.ts")
	assertContainsFile(t, path, `from "@oh-my-pi/pi-coding-agent"`)
	assertContainsFile(t, path, `["ingest", "omp", event]`)
	assertContainsFile(t, path, "TRACE_OMP_NESTED")
}
