package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestFallbackMemoryCheckpointSideRefAndRecall(t *testing.T) {
	repo := testRepo(t)
	if err := initTrace(repo); err != nil {
		t.Fatalf("initTrace: %v", err)
	}
	writeFile(t, filepath.Join(repo, "feature.txt"), "memory fallback\n")
	git(t, repo, "add", ".")
	git(t, repo, "commit", "-m", "Add fallback memory")

	record, err := commitTrace(repo)
	if err != nil {
		t.Fatalf("commitTrace: %v", err)
	}
	if len(record.Sessions) != 0 {
		t.Fatalf("expected fallback record, got sessions: %#v", record.Sessions)
	}
	out := git(t, repo, "show", checkpointRef+":"+record.ID+"/checkpoint.json")
	if !strings.Contains(out, "Add fallback memory") {
		t.Fatalf("checkpoint did not contain commit message: %s", out)
	}
	mem := git(t, repo, "show", memoryRef+":"+record.Commit+".md")
	if !strings.Contains(mem, "diff fallback") {
		t.Fatalf("memory ref did not contain fallback note: %s", mem)
	}
	if _, err := os.Stat(filepath.Join(repo, ".trace", "commits", record.Commit+".md")); !os.IsNotExist(err) {
		t.Fatalf("memory note should not dirty the worktree; stat err = %v", err)
	}

	t.Chdir(repo)
	var recall bytes.Buffer
	if err := recallMemory("fallback", &recall); err != nil {
		t.Fatalf("recallMemory: %v", err)
	}
	if !strings.Contains(recall.String(), memoryRef+":"+record.Commit+".md") {
		t.Fatalf("recall did not find memory: %s", recall.String())
	}
	var show bytes.Buffer
	if err := showMemory("HEAD", &show); err != nil {
		t.Fatalf("showMemory: %v", err)
	}
	if !strings.Contains(show.String(), "Checkpoint:") {
		t.Fatalf("show did not display memory: %s", show.String())
	}
}

func TestAgentMemoryFileWriteAndCheckpoint(t *testing.T) {
	repo := testRepo(t)
	if err := initTrace(repo); err != nil {
		t.Fatalf("initTrace: %v", err)
	}
	transcript := filepath.Join(repo, "codex-rollout.jsonl")
	writeFile(t, transcript, strings.Join([]string{
		`{"token":"supersecret","message":"implemented trace"}`,
		`{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"please add parser"}]}}`,
		`{"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch\n*** Add File: trace/parser.go\n+package main\n*** End Patch\n"}}`,
	}, "\n")+"\n")
	payload := []byte(`{"session_id":"codex-2","transcript_path":"` + transcript + `","prompt":"implement trace"}`)
	if err := captureAgentHook(repo, "codex", "user-prompt-submit", payload); err != nil {
		t.Fatalf("captureAgentHook: %v", err)
	}
	writeFile(t, filepath.Join(repo, "agent.txt"), "agent memory\n")
	git(t, repo, "add", ".")
	git(t, repo, "commit", "-m", "Add agent memory")
	record, err := commitTrace(repo)
	if err != nil {
		t.Fatalf("commitTrace: %v", err)
	}
	if len(record.Sessions) != 1 {
		t.Fatalf("expected one captured session, got %d", len(record.Sessions))
	}
	mem := git(t, repo, "show", memoryRef+":"+record.Commit+".md")
	if !strings.Contains(mem, "captured agent sessions") {
		t.Fatalf("memory did not mention agent source: %s", mem)
	}
	raw := git(t, repo, "show", checkpointRef+":"+record.ID+"/checkpoint.json")
	if strings.Contains(raw, "supersecret") || !strings.Contains(raw, "[REDACTED]") {
		t.Fatalf("checkpoint redaction failed: %s", raw)
	}
	for _, want := range []string{`"messages"`, "please add parser", `"tool_calls"`, "trace/parser.go"} {
		if !strings.Contains(raw, want) {
			t.Fatalf("checkpoint missing parsed Codex transcript %q: %s", want, raw)
		}
	}
}

func TestClaudeStopSentinelDetection(t *testing.T) {
	repo := testRepo(t)
	started := time.Now().UTC()
	transcript := filepath.Join(repo, "claude.jsonl")
	writeFile(t, transcript, `{"timestamp":"`+started.Format(time.RFC3339Nano)+`","tool_input":{"command":"trace hooks claude-code stop"}}`+"\n")
	if !hasClaudeStopSentinel(transcript, started) {
		t.Fatalf("expected Claude stop sentinel")
	}
}
