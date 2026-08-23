package main

import (
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCodexCapture(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"codex-1","transcript_path":"/tmp/codex.jsonl","prompt":"change it"}`)
	if err := captureSessionEvent(repo, "codex", "user-prompt-submit", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".trace", "sessions", "codex", "codex-1.jsonl"), "user-prompt-submit")
}

func TestCaptureRequiresSessionID(t *testing.T) {
	repo := testRepo(t)
	err := captureSessionEvent(repo, "custom-ai", "turn", []byte(`{"prompt":"change it"}`))
	if err == nil || !strings.Contains(err.Error(), "session_id") {
		t.Fatalf("expected session_id error, got %v", err)
	}
}

func TestClaudeCapture(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"claude-1","transcript_path":"/tmp/claude.jsonl","prompt":"change it"}`)
	if err := captureSessionEvent(repo, "claude-code", "user-prompt-submit", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".trace", "sessions", "claude-code", "claude-1.jsonl"), "claude-code")
}

func TestClaudeStopCaptureUsesTranscriptSentinel(t *testing.T) {
	repo := testRepo(t)
	transcript := filepath.Join(repo, "claude.jsonl")
	now := time.Now().UTC()
	writeFile(t, transcript, `{"timestamp":"`+now.Format(time.RFC3339Nano)+`","tool_input":{"command":"trace hooks claude-code stop"}}`+"\n")
	payload := []byte(`{"session_id":"claude-2","transcript_path":"` + transcript + `"}`)
	if err := captureSessionEvent(repo, "claude-code", "stop", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".trace", "sessions", "claude-code", "claude-2.jsonl"), "stop")
}

func TestOpenCodeCapture(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"open-1","prompt":"change it"}`)
	if err := captureSessionEvent(repo, "opencode", "turn-start", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".trace", "sessions", "opencode", "open-1.jsonl"), "turn-start")
}

func TestOpenCodeCaptureExportsTranscript(t *testing.T) {
	repo := testRepo(t)
	t.Setenv("TRACE_TEST_OPENCODE_MOCK_EXPORT", "1")
	writeFile(t, openCodeTranscriptPath(repo, "open-2"), `{"messages":[{"role":"user","text":"change it"}]}`)
	payload := []byte(`{"session_id":"open-2","prompt":"change it"}`)
	if err := captureSessionEvent(repo, "opencode", "turn-end", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	got := readFile(t, filepath.Join(repo, ".trace", "sessions", "opencode", "open-2.jsonl"))
	if !strings.Contains(got, "turn-end") || !strings.Contains(got, filepath.ToSlash(openCodeTranscriptPath(repo, "open-2"))) {
		t.Fatalf("missing OpenCode transcript capture: %s", got)
	}
}
