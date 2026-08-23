package main

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
)

func TestCapturedSessionPersistsMetadataBeforeCommit(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{
  "session_id":"generic-session-id",
  "model":"model-a",
  "token":"top-secret",
  "messages":[
    {"role":"user","text":"inspect token=hidden"},
    {"role":"assistant","text":"done"}
  ]
}`)
	if err := captureSessionEvent(repo, "cursor", "snapshot", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}

	record, found, err := readSessionRecord(repo, "cursor", "generic-session-id")
	if err != nil || !found {
		t.Fatalf("read durable session: found=%v err=%v", found, err)
	}
	if record.SchemaVersion != schemaVersion || record.Source != "cursor" || record.Branch == "" {
		t.Fatalf("unexpected identity metadata: %#v", record)
	}
	if record.StartedAt == "" || record.UpdatedAt == "" || record.MessageCount != 2 || record.EventCount != 1 {
		t.Fatalf("unexpected session metadata: %#v", record)
	}
	if record.TranscriptStatus != "not_provided" || record.TranscriptUnavailableReason != "" {
		t.Fatalf("unexpected transcript status: %#v", record)
	}
	if len(record.Models) != 1 || record.Models[0] != "model-a" {
		t.Fatalf("unexpected models: %v", record.Models)
	}
	if len(record.Checkpoints) != 0 || strings.Contains(record.Messages[0].Text, "hidden") || !strings.Contains(record.Messages[0].Text, "[REDACTED]") {
		t.Fatalf("unexpected durable content: %#v", record)
	}
	durableEvents, err := json.Marshal(record.Events)
	if err != nil {
		t.Fatalf("marshal durable events: %v", err)
	}
	if strings.Contains(string(durableEvents), "top-secret") || strings.Contains(string(durableEvents), "hidden") {
		t.Fatalf("durable events contain secrets: %s", durableEvents)
	}
	if status := strings.TrimSpace(git(t, repo, "status", "--porcelain")); status != "" {
		t.Fatalf("session storage dirtied the branch: %s", status)
	}
}

func TestSessionSpansMultipleCheckpoints(t *testing.T) {
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
	first, err := checkpointSessions(repo)
	if err != nil {
		t.Fatalf("link first commit: %v", err)
	}
	firstSHA := strings.TrimSpace(git(t, repo, "rev-parse", "HEAD"))

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
	second, err := checkpointSessions(repo)
	if err != nil {
		t.Fatalf("link second commit: %v", err)
	}
	secondSHA := strings.TrimSpace(git(t, repo, "rev-parse", "HEAD"))

	if len(first.Sessions) != 1 || first.Sessions[0].SessionID != sessionID || len(second.Sessions) != 1 {
		t.Fatalf("unexpected checkpoint pointers: first=%#v second=%#v", first.Sessions, second.Sessions)
	}
	note := git(t, repo, "notes", "--ref="+noteRef, "show", firstSHA)
	if strings.Contains(note, "message_from") || strings.Contains(note, "add parser") || !strings.Contains(note, sessionID) {
		t.Fatalf("commit note should contain only session pointers: %s", note)
	}
	session, found, err := readSessionRecord(repo, "codex", sessionID)
	if err != nil || !found {
		t.Fatalf("read session: found=%v err=%v", found, err)
	}
	if len(session.Checkpoints) != 2 {
		t.Fatalf("expected two checkpoints: %#v", session.Checkpoints)
	}
	if got := session.Checkpoints[0]; got.Commit.Subject != "add parser" || len(got.Commit.Files) != 1 || got.Commit.Files[0] != "parser.go" || got.MessageFrom != 1 || got.MessageThrough != 2 {
		t.Fatalf("unexpected first range: %#v", got)
	}
	if got := session.Checkpoints[1]; got.Commit.Subject != "handle empty input" || got.MessageFrom != 3 || got.MessageThrough != 4 {
		t.Fatalf("unexpected second range: %#v", got)
	}

	t.Chdir(repo)
	var firstOut bytes.Buffer
	if err := showCommitConversation(firstSHA, false, &firstOut); err != nil {
		t.Fatalf("show first commit: %v", err)
	}
	assertOutputContains(t, firstOut.String(), sessionID, "add the parser", "[REDACTED]", "model-a")
	assertOutputExcludes(t, firstOut.String(), "handle empty input", "hidden")

	var secondOut bytes.Buffer
	if err := showCommitConversation(secondSHA, false, &secondOut); err != nil {
		t.Fatalf("show second commit: %v", err)
	}
	assertOutputContains(t, secondOut.String(), sessionID, "handle empty input", "empty input handled")
	assertOutputExcludes(t, secondOut.String(), "add the parser")

	var commitJSON bytes.Buffer
	if err := showCommitConversation(secondSHA, true, &commitJSON); err != nil {
		t.Fatalf("show second commit JSON: %v", err)
	}
	var view commitView
	if err := json.Unmarshal(commitJSON.Bytes(), &view); err != nil {
		t.Fatalf("parse commit JSON: %v\n%s", err, commitJSON.String())
	}
	if view.Commit.SHA != secondSHA || len(view.Sessions) != 1 || view.Sessions[0].SessionID != sessionID {
		t.Fatalf("unexpected commit JSON: %#v", view)
	}

	var sessionOut bytes.Buffer
	if err := showSessionConversation(sessionID, false, &sessionOut); err != nil {
		t.Fatalf("show full session: %v", err)
	}
	assertOutputContains(t, sessionOut.String(), sessionID, firstSHA, secondSHA, "add the parser", "handle empty input")
}

func TestCommitCanLinkMultipleSessions(t *testing.T) {
	repo := testRepo(t)
	for _, item := range []struct {
		source string
		id     string
		text   string
	}{
		{source: "codex", id: "codex-session-full-id", text: "change the model"},
		{source: "claude-code", id: "claude-session-full-id", text: "review the model"},
	} {
		transcript := filepath.Join(t.TempDir(), item.id+".json")
		writeTranscript(t, transcript, conversationMessage{Role: "user", Text: item.text})
		payload, _ := json.Marshal(map[string]string{"session_id": item.id, "transcript_path": transcript})
		if err := captureSessionEvent(repo, item.source, "user-prompt-submit", payload); err != nil {
			t.Fatalf("capture %s: %v", item.source, err)
		}
	}
	writeFile(t, filepath.Join(repo, "model.go"), "package model\n")
	git(t, repo, "add", "model.go")
	git(t, repo, "commit", "-m", "change model")
	record, err := checkpointSessions(repo)
	if err != nil {
		t.Fatalf("link commit: %v", err)
	}
	if len(record.Sessions) != 2 {
		t.Fatalf("expected two linked sessions, got %#v", record.Sessions)
	}
	refs := strings.Fields(git(t, repo, "for-each-ref", "--format=%(refname)", sessionRefPrefix+"/"))
	if len(refs) != 2 || refs[0] == refs[1] {
		t.Fatalf("expected an independent ref per session, got %v", refs)
	}

	t.Chdir(repo)
	var out bytes.Buffer
	if err := showCommitConversation("HEAD", false, &out); err != nil {
		t.Fatalf("show commit: %v", err)
	}
	assertOutputContains(t, out.String(), "codex-session-full-id", "claude-session-full-id", "change the model", "review the model")
}

func TestCommitOnlyLinksSessionsFromItsWorktree(t *testing.T) {
	repo := testRepo(t)
	worktree := filepath.Join(t.TempDir(), "worktree")
	git(t, repo, "worktree", "add", "-b", "other-worktree", worktree)
	for _, item := range []struct {
		root string
		id   string
	}{
		{root: repo, id: "main-session"},
		{root: worktree, id: "other-session"},
	} {
		payload := []byte(`{"session_id":"` + item.id + `","prompt":"change it"}`)
		if err := captureSessionEvent(item.root, "custom-ai", "turn", payload); err != nil {
			t.Fatalf("capture %s: %v", item.id, err)
		}
	}
	writeFile(t, filepath.Join(repo, "main.go"), "package main\n")
	git(t, repo, "add", "main.go")
	git(t, repo, "commit", "-m", "change main worktree")
	record, err := checkpointSessions(repo)
	if err != nil {
		t.Fatalf("link commit: %v", err)
	}
	if len(record.Sessions) != 1 || record.Sessions[0].SessionID != "main-session" {
		t.Fatalf("expected only the main worktree session, got %#v", record.Sessions)
	}
}

func TestGenericIngestAndJSONViews(t *testing.T) {
	repo := testRepo(t)
	t.Chdir(repo)
	payload := `{"session_id":"tool-session","model":"model-z","prompt":"improve the skill","response":"recorded"}`
	var output bytes.Buffer
	a := app{stdin: strings.NewReader(payload), stdout: &output, stderr: &output}
	if err := a.run([]string{"ingest", "my-ai", "turn"}); err != nil {
		t.Fatalf("ingest: %v", err)
	}

	output.Reset()
	if err := a.run([]string{"sessions", "--json"}); err != nil {
		t.Fatalf("list sessions: %v", err)
	}
	var summaries []sessionSummary
	if err := json.Unmarshal(output.Bytes(), &summaries); err != nil {
		t.Fatalf("parse session list: %v\n%s", err, output.String())
	}
	if len(summaries) != 1 || summaries[0].SchemaVersion != schemaVersion || summaries[0].SessionID != "tool-session" || summaries[0].Source != "my-ai" {
		t.Fatalf("unexpected summaries: %#v", summaries)
	}

	output.Reset()
	if err := a.run([]string{"session", "tool-session", "--json"}); err != nil {
		t.Fatalf("show session JSON: %v", err)
	}
	var session sessionRecord
	if err := json.Unmarshal(output.Bytes(), &session); err != nil {
		t.Fatalf("parse session JSON: %v\n%s", err, output.String())
	}
	if session.ID != "tool-session" || session.Source != "my-ai" || session.MessageCount != 2 {
		t.Fatalf("unexpected session JSON: %#v", session)
	}
}

func TestParseCodexTranscriptMessage(t *testing.T) {
	data := []byte(`{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"please add parser"}]}}`)
	messages := parseTranscriptMessages(data)
	if len(messages) != 1 || messages[0].Role != "user" || messages[0].Text != "please add parser" {
		t.Fatalf("unexpected messages: %#v", messages)
	}
}

func TestTranscriptAvailabilityIsExplicit(t *testing.T) {
	repo := testRepo(t)
	payload := []byte(`{"session_id":"missing-transcript","transcript_path":"/does/not/exist","prompt":"keep the fallback"}`)
	if err := captureSessionEvent(repo, "custom-ai", "turn", payload); err != nil {
		t.Fatalf("captureSessionEvent: %v", err)
	}
	record, found, err := readSessionRecord(repo, "custom-ai", "missing-transcript")
	if err != nil || !found {
		t.Fatalf("read session: found=%v err=%v", found, err)
	}
	if record.TranscriptStatus != "unavailable" || record.TranscriptUnavailableReason != "unreadable" {
		t.Fatalf("unexpected transcript availability: %#v", record)
	}
	if len(record.Messages) != 1 || record.Messages[0].Text != "keep the fallback" {
		t.Fatalf("expected fallback prompt, got %#v", record.Messages)
	}
	data, err := json.Marshal(record.Events)
	if err != nil {
		t.Fatalf("marshal events: %v", err)
	}
	if strings.Contains(string(data), "/does/not/exist") {
		t.Fatalf("durable events contain a local transcript path: %s", data)
	}
}

func captureSession(t *testing.T, repo string, sessionID string, transcript string, event string) {
	t.Helper()
	payload, err := json.Marshal(map[string]string{"session_id": sessionID, "transcript_path": transcript, "model": "model-a"})
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	if err := captureSessionEvent(repo, "codex", event, payload); err != nil {
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
