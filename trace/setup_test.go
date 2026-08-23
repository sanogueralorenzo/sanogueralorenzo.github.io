package main

import (
	"bytes"
	"path/filepath"
	"strings"
	"testing"
)

func TestInit(t *testing.T) {
	repo := testRepo(t)
	if err := initTrace(repo); err != nil {
		t.Fatalf("initTrace: %v", err)
	}
	assertExists(t, filepath.Join(repo, ".trace", "sessions"))
	assertContainsFile(t, filepath.Join(repo, ".git", "info", "exclude"), ".trace/")
	if got := strings.TrimSpace(git(t, repo, "check-ignore", ".trace/state.json")); got != ".trace/state.json" {
		t.Fatalf("expected Trace state to be ignored, got %q", got)
	}
}

func TestInitPreservesLocalExcludes(t *testing.T) {
	repo := testRepo(t)
	exclude := filepath.Join(repo, ".git", "info", "exclude")
	writeFile(t, exclude, "local-only.txt\n")
	if err := initTrace(repo); err != nil {
		t.Fatalf("initTrace: %v", err)
	}
	if err := initTrace(repo); err != nil {
		t.Fatalf("initTrace again: %v", err)
	}
	assertContainsFile(t, exclude, "local-only.txt")
	if got := strings.Count(readFile(t, exclude), ".trace/"); got != 1 {
		t.Fatalf("expected one Trace exclude, got %d", got)
	}
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

func TestEnablePreservesExistingGitHook(t *testing.T) {
	repo := testRepo(t)
	hook := filepath.Join(repo, ".git", "hooks", "post-commit")
	writeFile(t, hook, "#!/bin/sh\nprintf 'custom hook\\n'\n")
	var out bytes.Buffer
	if err := enableTrace(repo, &out); err != nil {
		t.Fatalf("enableTrace: %v", err)
	}
	if err := enableTrace(repo, &out); err != nil {
		t.Fatalf("enableTrace again: %v", err)
	}
	assertContainsFile(t, hook, "custom hook")
	assertContainsFile(t, hook, "trace hooks git post-commit")
	if got := strings.Count(readFile(t, hook), "trace hooks git post-commit"); got != 1 {
		t.Fatalf("expected one Trace hook, got %d", got)
	}
}
