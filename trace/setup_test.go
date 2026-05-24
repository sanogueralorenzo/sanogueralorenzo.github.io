package main

import (
	"bytes"
	"path/filepath"
	"testing"
)

func TestInit(t *testing.T) {
	repo := testRepo(t)
	if err := initTrace(repo); err != nil {
		t.Fatalf("initTrace: %v", err)
	}
	assertExists(t, filepath.Join(repo, ".trace", "config.json"))
	assertExists(t, filepath.Join(repo, ".trace", "sessions"))
}

func TestEnableInstallsGitAndAgentHooks(t *testing.T) {
	repo := testRepo(t)
	var out bytes.Buffer
	if err := enableTrace(repo, &out); err != nil {
		t.Fatalf("enableTrace: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".git", "hooks", "post-commit"), "trace hooks git post-commit")
	assertContainsFile(t, filepath.Join(repo, ".codex", "hooks.json"), "trace hooks codex user-prompt-submit")
	assertContainsFile(t, filepath.Join(repo, ".claude", "settings.json"), "trace hooks claude-code session-start")
	assertContainsFile(t, filepath.Join(repo, ".opencode", "plugins", "trace.ts"), "TracePlugin")
}
