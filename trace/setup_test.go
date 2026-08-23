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
	assertExists(t, mustTraceDataPath(t, repo, "sessions"))
	if got := strings.TrimSpace(git(t, repo, "status", "--porcelain")); got != "" {
		t.Fatalf("Trace storage dirtied the branch: %s", got)
	}
}

func TestInitUsesGitCommonDirAcrossWorktrees(t *testing.T) {
	repo := testRepo(t)
	worktree := filepath.Join(t.TempDir(), "worktree")
	git(t, repo, "worktree", "add", "-b", "trace-worktree", worktree)
	if err := initTrace(worktree); err != nil {
		t.Fatalf("initTrace worktree: %v", err)
	}
	gotCommon, err := gitCommonDir(worktree)
	if err != nil {
		t.Fatalf("worktree common dir: %v", err)
	}
	wantCommon, err := gitCommonDir(repo)
	if err != nil {
		t.Fatalf("repository common dir: %v", err)
	}
	if gotCommon != wantCommon {
		t.Fatalf("worktrees should share the Git common dir: got %s want %s", gotCommon, wantCommon)
	}
	if got, other := mustTraceDataPath(t, worktree), mustTraceDataPath(t, repo); got == other {
		t.Fatalf("worktrees should isolate live Trace state: %s", got)
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
