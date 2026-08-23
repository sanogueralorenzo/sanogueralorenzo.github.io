package main

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
)

func TestSessionSpansMultipleCommits(t *testing.T) {
	repo := testRepo(t)
	transcript := filepath.Join(t.TempDir(), "session.json")
	sessionID := "019d2a5f-5e87-7a31-9f8b-4c29c7de1024"

	writeTranscript(t, transcript,
		conversationMessage{Role: "user", Text: "add the parser token=hidden"},
		conversationMessage{Role: "assistant", Text: "parser added"},
	)
	captureSession(t, repo, sessionID, transcript, "user-prompt-submit")
	writeFile(t, filepath.Join(repo, "parser.go"), "package parser\n")
	git(t, repo, "add", "parser.go")
	git(t, repo, "commit", "-m", "add parser")
	first, err := linkCommitConversations(repo)
	if err != nil {
		t.Fatalf("link first commit: %v", err)
	}

	writeTranscript(t, transcript,
		conversationMessage{Role: "user", Text: "add the parser token=hidden"},
		conversationMessage{Role: "assistant", Text: "parser added"},
		conversationMessage{Role: "user", Text: "handle empty input"},
		conversationMessage{Role: "assistant", Text: "empty input handled"},
	)
	captureSession(t, repo, sessionID, transcript, "post-tool-use")
	writeFile(t, filepath.Join(repo, "empty.go"), "package parser\n")
	git(t, repo, "add", "empty.go")
	git(t, repo, "commit", "-m", "handle empty input")
	second, err := linkCommitConversations(repo)
	if err != nil {
		t.Fatalf("link second commit: %v", err)
	}

	if got := first.Sessions[0]; got.SessionID != sessionID || got.MessageFrom != 1 || got.MessageThrough != 2 {
		t.Fatalf("unexpected first link: %#v", got)
	}
	if got := second.Sessions[0]; got.SessionID != sessionID || got.MessageFrom != 3 || got.MessageThrough != 4 {
		t.Fatalf("unexpected second link: %#v", got)
	}

	t.Chdir(repo)
	var firstOut bytes.Buffer
	if err := showCommitConversation(first.Commit, &firstOut); err != nil {
		t.Fatalf("show first commit: %v", err)
	}
	assertOutputContains(t, firstOut.String(), sessionID, "add the parser", "[REDACTED]")
	assertOutputExcludes(t, firstOut.String(), "handle empty input", "hidden")

	var secondOut bytes.Buffer
	if err := showCommitConversation(second.Commit, &secondOut); err != nil {
		t.Fatalf("show second commit: %v", err)
	}
	assertOutputContains(t, secondOut.String(), sessionID, "handle empty input", "empty input handled")
	assertOutputExcludes(t, secondOut.String(), "add the parser")

	var sessionOut bytes.Buffer
	if err := showSessionConversation(sessionID, &sessionOut); err != nil {
		t.Fatalf("show full session: %v", err)
	}
	assertOutputContains(t, sessionOut.String(), sessionID, first.Commit, second.Commit, "add the parser", "handle empty input")

	paths := strings.Fields(git(t, repo, "ls-tree", "-r", "--name-only", sessionRef))
	if len(paths) != 1 {
		t.Fatalf("expected one durable session record, got %v", paths)
	}
}

func TestCommitCanLinkMultipleSessions(t *testing.T) {
	repo := testRepo(t)
	for _, item := range []struct {
		agent string
		id    string
		text  string
	}{
		{agent: "codex", id: "codex-session-full-id", text: "change the model"},
		{agent: "claude-code", id: "claude-session-full-id", text: "review the model"},
	} {
		transcript := filepath.Join(t.TempDir(), item.id+".json")
		writeTranscript(t, transcript, conversationMessage{Role: "user", Text: item.text})
		payload, _ := json.Marshal(map[string]string{"session_id": item.id, "transcript_path": transcript})
		if err := captureAgentHook(repo, item.agent, "user-prompt-submit", payload); err != nil {
			t.Fatalf("capture %s: %v", item.agent, err)
		}
	}
	writeFile(t, filepath.Join(repo, "model.go"), "package model\n")
	git(t, repo, "add", "model.go")
	git(t, repo, "commit", "-m", "change model")
	record, err := linkCommitConversations(repo)
	if err != nil {
		t.Fatalf("link commit: %v", err)
	}
	if len(record.Sessions) != 2 {
		t.Fatalf("expected two linked sessions, got %#v", record.Sessions)
	}

	t.Chdir(repo)
	var out bytes.Buffer
	if err := showCommitConversation(record.Commit, &out); err != nil {
		t.Fatalf("show commit: %v", err)
	}
	assertOutputContains(t, out.String(), "codex-session-full-id", "claude-session-full-id", "change the model", "review the model")
}

func TestParseCodexTranscriptMessage(t *testing.T) {
	data := []byte(`{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"please add parser"}]}}`)
	messages := parseTranscriptMessages(data)
	if len(messages) != 1 || messages[0].Role != "user" || messages[0].Text != "please add parser" {
		t.Fatalf("unexpected messages: %#v", messages)
	}
}

func captureSession(t *testing.T, repo string, sessionID string, transcript string, event string) {
	t.Helper()
	payload, err := json.Marshal(map[string]string{"session_id": sessionID, "transcript_path": transcript})
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	if err := captureAgentHook(repo, "codex", event, payload); err != nil {
		t.Fatalf("capture session: %v", err)
	}
}

func writeTranscript(t *testing.T, path string, messages ...conversationMessage) {
	t.Helper()
	data, err := json.Marshal(map[string]any{"messages": messages})
	if err != nil {
		t.Fatalf("marshal transcript: %v", err)
	}
	writeFile(t, path, string(data))
}

func assertOutputContains(t *testing.T, got string, values ...string) {
	t.Helper()
	for _, value := range values {
		if !strings.Contains(got, value) {
			t.Fatalf("output missing %q:\n%s", value, got)
		}
	}
}

func assertOutputExcludes(t *testing.T, got string, values ...string) {
	t.Helper()
	for _, value := range values {
		if strings.Contains(got, value) {
			t.Fatalf("output unexpectedly contains %q:\n%s", value, got)
		}
	}
}
