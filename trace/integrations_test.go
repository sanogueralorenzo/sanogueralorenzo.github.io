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
	for _, event := range []string{"SessionStart", "UserPromptSubmit", "Stop", "PostToolUse"} {
		if len(file.Hooks[event]) == 0 {
			t.Fatalf("missing Codex event %s", event)
		}
	}
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
	if got := strings.Join(settings.Permissions["deny"], "\n"); !strings.Contains(got, ".trace/sessions") {
		t.Fatalf("missing Claude deny rule: %s", got)
	}
}

func TestOpenCodePluginConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installOpenCodePlugin(repo); err != nil {
		t.Fatalf("installOpenCodePlugin: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".opencode", "plugins", "trace.ts"), "trace hooks opencode turn-start")
}
