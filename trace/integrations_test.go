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
	if len(settings.Hooks["PreToolUse"]) == 0 || len(settings.Hooks["PostToolUse"]) == 0 {
		t.Fatalf("missing Claude task hooks: %#v", settings.Hooks)
	}
	if !hasMatcherCommand(settings.Hooks["PreToolUse"], "Task", "trace hooks claude-code pre-task") {
		t.Fatalf("missing Claude Task pre hook: %#v", settings.Hooks["PreToolUse"])
	}
	if !hasMatcherCommand(settings.Hooks["PostToolUse"], "Task", "trace hooks claude-code post-task") {
		t.Fatalf("missing Claude Task post hook: %#v", settings.Hooks["PostToolUse"])
	}
	if got := strings.Join(settings.Permissions["deny"], "\n"); !strings.Contains(got, ".trace/sessions") {
		t.Fatalf("missing Claude deny rule: %s", got)
	}
}

func TestCodexTraceOwnedHooksAreReplaced(t *testing.T) {
	repo := testRepo(t)
	writeFile(t, filepath.Join(repo, ".codex", "hooks.json"), `{"hooks":{"Stop":[{"matcher":null,"hooks":[{"type":"command","command":"trace hooks codex old-stop","timeout":30},{"type":"command","command":"custom hook"}]}]}}`)
	if err := installCodexHooks(repo); err != nil {
		t.Fatalf("installCodexHooks: %v", err)
	}
	got := readFile(t, filepath.Join(repo, ".codex", "hooks.json"))
	if strings.Contains(got, "old-stop") {
		t.Fatalf("old Trace hook was not replaced: %s", got)
	}
	if !strings.Contains(got, "custom hook") || !strings.Contains(got, "trace hooks codex stop") {
		t.Fatalf("expected custom hook preserved and new Trace hook installed: %s", got)
	}
}

func TestClaudeTraceOwnedHooksAreReplaced(t *testing.T) {
	repo := testRepo(t)
	writeFile(t, filepath.Join(repo, ".claude", "settings.json"), `{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"trace hooks claude-code old-stop"},{"type":"command","command":"custom hook"}]}]}}`)
	if err := installClaudeHooks(repo); err != nil {
		t.Fatalf("installClaudeHooks: %v", err)
	}
	got := readFile(t, filepath.Join(repo, ".claude", "settings.json"))
	if strings.Contains(got, "old-stop") {
		t.Fatalf("old Trace hook was not replaced: %s", got)
	}
	if !strings.Contains(got, "custom hook") || !strings.Contains(got, "trace hooks claude-code stop") {
		t.Fatalf("expected custom hook preserved and new Trace hook installed: %s", got)
	}
}

func TestOpenCodePluginConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installOpenCodePlugin(repo); err != nil {
		t.Fatalf("installOpenCodePlugin: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".opencode", "plugins", "trace.ts"), "trace hooks opencode turn-start")
	assertContainsFile(t, filepath.Join(repo, ".opencode", "plugins", "trace.ts"), "trace hooks opencode turn-end")
}

func hasMatcherCommand(groups []hookMatcher, matcher string, command string) bool {
	for _, group := range groups {
		if group.Matcher == nil || *group.Matcher != matcher {
			continue
		}
		for _, hook := range group.Hooks {
			if hook.Command == command {
				return true
			}
		}
	}
	return false
}
