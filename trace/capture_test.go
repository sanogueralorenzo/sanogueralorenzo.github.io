package main

import (
	"path/filepath"
	"testing"
)

func TestCodexCapture(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"codex-1","transcript_path":"/tmp/codex.jsonl","prompt":"change it"}`)
	if err := captureAgentHook(repo, "codex", "user-prompt-submit", payload); err != nil {
		t.Fatalf("captureAgentHook: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".trace", "sessions", "codex", "codex-1.jsonl"), "user-prompt-submit")
}

func TestClaudeCapture(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"claude-1","transcript_path":"/tmp/claude.jsonl","prompt":"change it"}`)
	if err := captureAgentHook(repo, "claude-code", "user-prompt-submit", payload); err != nil {
		t.Fatalf("captureAgentHook: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".trace", "sessions", "claude-code", "claude-1.jsonl"), "claude-code")
}

func TestOpenCodeCapture(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"open-1","prompt":"change it"}`)
	if err := captureAgentHook(repo, "opencode", "turn-start", payload); err != nil {
		t.Fatalf("captureAgentHook: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".trace", "sessions", "opencode", "open-1.jsonl"), "turn-start")
}
