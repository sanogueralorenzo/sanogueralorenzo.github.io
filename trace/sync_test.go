package main

import (
	"bytes"
	"path/filepath"
	"testing"
)

func TestPushAndFetchSurviveFreshClone(t *testing.T) {
	base := t.TempDir()
	remote := filepath.Join(base, "remote.git")
	git(t, base, "init", "--bare", remote)

	source := testRepo(t)
	git(t, source, "branch", "-M", "main")
	git(t, source, "remote", "add", "origin", remote)
	if err := captureSessionEvent(source, "test-ai", "turn-start", []byte(`{"session_id":"clone-session","prompt":"keep this conversation"}`)); err != nil {
		t.Fatalf("capture session: %v", err)
	}
	writeFile(t, filepath.Join(source, "change.txt"), "change\n")
	git(t, source, "add", "change.txt")
	git(t, source, "commit", "-m", "record checkpoint")
	if _, err := checkpointSessions(source); err != nil {
		t.Fatalf("checkpoint session: %v", err)
	}
	git(t, source, "push", "-u", "origin", "main")
	var output bytes.Buffer
	t.Chdir(source)
	if err := (app{stdout: &output}).run([]string{"push", "origin"}); err != nil {
		t.Fatalf("push Trace refs: %v", err)
	}
	assertOutputContains(t, output.String(), "trace refs pushed to origin")

	clone := filepath.Join(base, "clone")
	git(t, base, "clone", "--branch", "main", remote, clone)
	if records, err := listSessionRecords(clone); err != nil || len(records) != 0 {
		t.Fatalf("normal clone should not fetch hidden refs: records=%#v err=%v", records, err)
	}
	output.Reset()
	t.Chdir(clone)
	if err := (app{stdout: &output}).run([]string{"fetch", "origin"}); err != nil {
		t.Fatalf("fetch Trace refs: %v", err)
	}
	assertOutputContains(t, output.String(), "trace refs fetched from origin")
	session, err := findSessionRecord(clone, "clone-session")
	if err != nil {
		t.Fatalf("find fetched session: %v", err)
	}
	if len(session.Checkpoints) != 1 || len(session.Messages) != 1 || session.Messages[0].Text != "keep this conversation" {
		t.Fatalf("unexpected fetched session: %#v", session)
	}
	view, err := buildCommitView(clone, "HEAD")
	if err != nil {
		t.Fatalf("show fetched checkpoint: %v", err)
	}
	if len(view.Sessions) != 1 || view.Sessions[0].SessionID != "clone-session" {
		t.Fatalf("unexpected fetched checkpoint: %#v", view)
	}
}
