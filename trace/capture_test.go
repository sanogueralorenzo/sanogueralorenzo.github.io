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
	if err := captureSessionEvent(repo, "codex", "turn-start", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	assertContainsFile(t, mustTraceDataPath(t, repo, "sessions", "codex", "codex-1.jsonl"), "turn-start")
}

func TestCaptureRequiresSessionID(t *testing.T) {
	repo := testRepo(t)
	err := captureSessionEvent(repo, "custom-ai", "turn", []byte(`{"prompt":"change it"}`))
	if err == nil || !strings.Contains(err.Error(), "session_id") {
		t.Fatalf("expected session_id error, got %v", err)
	}
}

func TestAgentHooksUseIngest(t *testing.T) {
	a := app{stdin: strings.NewReader(`{"session_id":"session"}`)}
	err := a.run([]string{"hooks", "codex", "turn-start"})
	if err == nil || err.Error() != "usage: trace hooks git post-commit" {
		t.Fatalf("expected agent hooks to be rejected, got %v", err)
	}
}

func TestClaudeCapture(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"claude-1","transcript_path":"/tmp/claude.jsonl","prompt":"change it"}`)
	if err := captureSessionEvent(repo, "claude-code", "turn-start", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	assertContainsFile(t, mustTraceDataPath(t, repo, "sessions", "claude-code", "claude-1.jsonl"), "claude-code")
}

func TestClaudeStopCaptureUsesTranscriptSentinel(t *testing.T) {
	repo := testRepo(t)
	transcript := filepath.Join(repo, "claude.jsonl")
	now := time.Now().UTC()
	writeFile(t, transcript, `{"timestamp":"`+now.Format(time.RFC3339Nano)+`","tool_input":{"command":"trace ingest claude-code turn-end"}}`+"\n")
	payload := []byte(`{"session_id":"claude-2","transcript_path":"` + transcript + `"}`)
	if err := captureSessionEvent(repo, "claude-code", "turn-end", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	assertContainsFile(t, mustTraceDataPath(t, repo, "sessions", "claude-code", "claude-2.jsonl"), "turn-end")
}

func TestClaudeTurnEndUsesSettledTranscript(t *testing.T) {
	repo := testRepo(t)
	transcript := filepath.Join(repo, "claude.jsonl")
	writeFile(t, transcript, `{"type":"message"}`+"\n")
	started := time.Now()
	waitForClaudeTranscriptFlush(transcript, started)
	if elapsed := time.Since(started); elapsed < 500*time.Millisecond || elapsed >= 2*time.Second {
		t.Fatalf("unexpected settle wait: %s", elapsed)
	}
}

func TestOpenCodeCapture(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"open-1","prompt":"change it"}`)
	if err := captureSessionEvent(repo, "opencode", "turn-start", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	assertContainsFile(t, mustTraceDataPath(t, repo, "sessions", "opencode", "open-1.jsonl"), "turn-start")
}

func TestOpenCodeCaptureExportsTranscript(t *testing.T) {
	repo := testRepo(t)
	t.Setenv("TRACE_TEST_OPENCODE_MOCK_EXPORT", "1")
	transcript, err := openCodeTranscriptPath(repo, "open-2")
	if err != nil {
		t.Fatalf("openCodeTranscriptPath: %v", err)
	}
	writeFile(t, transcript, `{"messages":[{"role":"user","text":"change it"}]}`)
	payload := []byte(`{"session_id":"open-2","prompt":"change it"}`)
	if err := captureSessionEvent(repo, "opencode", "turn-end", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	got := readFile(t, mustTraceDataPath(t, repo, "sessions", "opencode", "open-2.jsonl"))
	if !strings.Contains(got, "turn-end") || !strings.Contains(got, filepath.ToSlash(transcript)) {
		t.Fatalf("missing OpenCode transcript capture: %s", got)
	}
}

func TestOpenCodeTranscriptRefreshesAtCheckpoint(t *testing.T) {
	repo := testRepo(t)
	previous := exportOpenCodeTranscriptFn
	exports := 0
	exportOpenCodeTranscriptFn = func(root string, sessionID string) error {
		exports++
		path, err := openCodeTranscriptPath(root, sessionID)
		if err != nil {
			return err
		}
		messages := `{"messages":[{"role":"user","text":"commit this turn"}]}`
		if exports == 2 {
			messages = `{"messages":[{"role":"user","text":"commit this turn"},{"role":"assistant","text":"second commit"}]}`
		}
		writeFile(t, path, messages)
		return nil
	}
	t.Cleanup(func() { exportOpenCodeTranscriptFn = previous })

	if err := captureSessionEvent(repo, "opencode", "turn-start", []byte(`{"session_id":"open-checkpoint"}`)); err != nil {
		t.Fatalf("capture turn start: %v", err)
	}
	writeFile(t, filepath.Join(repo, "change.txt"), "change\n")
	git(t, repo, "add", "change.txt")
	git(t, repo, "commit", "-m", "change")
	if _, err := checkpointSessions(repo); err != nil {
		t.Fatalf("checkpointSessions: %v", err)
	}
	if exports != 1 {
		t.Fatalf("expected one checkpoint export, got %d", exports)
	}
	record, found, err := readSessionRecord(repo, "opencode", "open-checkpoint")
	if err != nil || !found || record.MessageCount != 1 || record.Messages[0].Text != "commit this turn" {
		t.Fatalf("unexpected refreshed record: found=%v err=%v record=%#v", found, err, record)
	}

	writeFile(t, filepath.Join(repo, "second.txt"), "second\n")
	git(t, repo, "add", "second.txt")
	git(t, repo, "commit", "-m", "second")
	if _, err := checkpointSessions(repo); err != nil {
		t.Fatalf("second checkpoint: %v", err)
	}
	record, found, err = readSessionRecord(repo, "opencode", "open-checkpoint")
	if err != nil || !found || exports != 2 || record.MessageCount != 2 || len(record.Checkpoints) != 2 {
		t.Fatalf("unexpected second checkpoint: exports=%d found=%v err=%v record=%#v", exports, found, err, record)
	}
}
