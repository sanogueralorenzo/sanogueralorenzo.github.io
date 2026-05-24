package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestInit(t *testing.T) {
	repo := testRepo(t)
	if err := initTrace(repo); err != nil {
		t.Fatalf("initTrace: %v", err)
	}
	assertExists(t, filepath.Join(repo, ".trace", "config.json"))
	assertExists(t, filepath.Join(repo, ".trace", "sessions"))
	assertExists(t, filepath.Join(repo, ".trace", "commits", ".gitkeep"))
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

func TestCodexHookConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installCodexHooks(repo); err != nil {
		t.Fatalf("installCodexHooks: %v", err)
	}
	var file hookFile
	readTestJSON(t, filepath.Join(repo, ".codex", "hooks.json"), &file)
	for _, event := range []string{"SessionStart", "UserPromptSubmit", "Stop", "PostToolUse"} {
		if len(file.Hooks[event]) == 0 {
			t.Fatalf("missing Codex event %s", event)
		}
	}
	assertContainsFile(t, filepath.Join(repo, ".codex", "config.toml"), "codex_hooks = true")
}

func TestClaudeHookConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installClaudeHooks(repo); err != nil {
		t.Fatalf("installClaudeHooks: %v", err)
	}
	var settings claudeSettings
	readTestJSON(t, filepath.Join(repo, ".claude", "settings.json"), &settings)
	for _, event := range []string{"SessionStart", "SessionEnd", "UserPromptSubmit", "Stop"} {
		if len(settings.Hooks[event]) == 0 {
			t.Fatalf("missing Claude event %s", event)
		}
	}
	if got := strings.Join(settings.Permissions["deny"], "\n"); !strings.Contains(got, ".trace/sessions") {
		t.Fatalf("missing Claude deny rule: %s", got)
	}
}

func TestOpenCodePluginConfig(t *testing.T) {
	repo := testRepo(t)
	if err := installOpenCodePlugin(repo); err != nil {
		t.Fatalf("installOpenCodePlugin: %v", err)
	}
	assertContainsFile(t, filepath.Join(repo, ".opencode", "plugins", "trace.ts"), "trace hooks opencode turn-start")
}

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
	assertContainsFile(t, filepath.Join(repo, ".trace", "commits", record.Commit+".md"), "diff fallback")
	out := git(t, repo, "show", checkpointRef+":"+record.ID+"/checkpoint.json")
	if !strings.Contains(out, "Add fallback memory") {
		t.Fatalf("checkpoint did not contain commit message: %s", out)
	}

	t.Chdir(repo)
	var recall bytes.Buffer
	if err := recallMemory("fallback", &recall); err != nil {
		t.Fatalf("recallMemory: %v", err)
	}
	if !strings.Contains(recall.String(), ".trace/commits/") {
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
	writeFile(t, transcript, `{"token":"supersecret","message":"implemented trace"}`+"\n")
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
	mem := readFile(t, filepath.Join(repo, ".trace", "commits", record.Commit+".md"))
	if !strings.Contains(mem, "captured agent sessions") {
		t.Fatalf("memory did not mention agent source: %s", mem)
	}
	raw := git(t, repo, "show", checkpointRef+":"+record.ID+"/checkpoint.json")
	if strings.Contains(raw, "supersecret") || !strings.Contains(raw, "[REDACTED]") {
		t.Fatalf("checkpoint redaction failed: %s", raw)
	}
}

func testRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	git(t, dir, "init")
	git(t, dir, "config", "user.email", "trace@example.com")
	git(t, dir, "config", "user.name", "Trace Test")
	writeFile(t, filepath.Join(dir, "README.md"), "test\n")
	git(t, dir, "add", "README.md")
	git(t, dir, "commit", "-m", "initial")
	return dir
}

func git(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return string(out)
}

func writeFile(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}

func assertExists(t *testing.T, path string) {
	t.Helper()
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("expected %s to exist: %v", path, err)
	}
}

func assertContainsFile(t *testing.T, path string, want string) {
	t.Helper()
	got := readFile(t, path)
	if !strings.Contains(got, want) {
		t.Fatalf("%s missing %q:\n%s", path, want, got)
	}
}

func readTestJSON(t *testing.T, path string, v any) {
	t.Helper()
	data := readFile(t, path)
	if err := json.Unmarshal([]byte(data), v); err != nil {
		t.Fatalf("unmarshal %s: %v\n%s", path, err, data)
	}
}
