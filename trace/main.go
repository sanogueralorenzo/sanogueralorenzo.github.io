package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const (
	traceDir      = ".trace"
	checkpointRef = "refs/trace/checkpoints/v1"
)

type app struct {
	stdin  io.Reader
	stdout io.Writer
	stderr io.Writer
}

func main() {
	a := app{stdin: os.Stdin, stdout: os.Stdout, stderr: os.Stderr}
	if err := a.run(os.Args[1:]); err != nil {
		fmt.Fprintln(a.stderr, err)
		os.Exit(1)
	}
}

func (a app) run(args []string) error {
	if len(args) == 0 {
		return usage(a.stdout)
	}
	switch args[0] {
	case "init":
		root, err := gitRoot(".")
		if err != nil {
			return err
		}
		if err := initTrace(root); err != nil {
			return err
		}
		fmt.Fprintln(a.stdout, "trace initialized")
		return nil
	case "enable":
		root, err := gitRoot(".")
		if err != nil {
			return err
		}
		if err := enableTrace(root, a.stdout); err != nil {
			return err
		}
		return nil
	case "hooks":
		return a.runHook(args[1:])
	case "show":
		if len(args) != 2 {
			return errors.New("usage: trace show <commit>")
		}
		return showMemory(args[1], a.stdout)
	case "recall":
		if len(args) < 2 {
			return errors.New("usage: trace recall <query>")
		}
		return recallMemory(strings.Join(args[1:], " "), a.stdout)
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func usage(w io.Writer) error {
	_, err := fmt.Fprintln(w, "usage: trace <init|enable|hooks|show|recall>")
	return err
}

func (a app) runHook(args []string) error {
	if len(args) < 2 {
		return errors.New("usage: trace hooks <git|codex|claude-code|opencode> <event>")
	}
	if args[0] == "git" {
		if args[1] != "post-commit" {
			return nil
		}
		root, err := gitRoot(".")
		if err != nil {
			return err
		}
		_, err = commitTrace(root)
		return err
	}
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	payload, err := io.ReadAll(a.stdin)
	if err != nil {
		return fmt.Errorf("read hook payload: %w", err)
	}
	return captureAgentHook(root, args[0], args[1], payload)
}

func gitRoot(dir string) (string, error) {
	out, err := command(dir, "git", "rev-parse", "--show-toplevel")
	if err != nil {
		return "", fmt.Errorf("not a git repository: %w", err)
	}
	return strings.TrimSpace(out), nil
}

func command(dir string, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			return "", fmt.Errorf("%s: %w", msg, err)
		}
		return "", err
	}
	return string(out), nil
}

func commandEnv(dir string, env []string, input []byte, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), env...)
	cmd.Stdin = bytes.NewReader(input)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			return "", fmt.Errorf("%s: %w", msg, err)
		}
		return "", err
	}
	return string(out), nil
}

func initTrace(root string) error {
	dirs := []string{
		filepath.Join(root, traceDir),
		filepath.Join(root, traceDir, "sessions"),
		filepath.Join(root, traceDir, "commits"),
		filepath.Join(root, traceDir, "archive"),
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o750); err != nil {
			return fmt.Errorf("create %s: %w", dir, err)
		}
	}
	configPath := filepath.Join(root, traceDir, "config.json")
	if _, err := os.Stat(configPath); errors.Is(err, os.ErrNotExist) {
		cfg := []byte("{\n  \"version\": 1,\n  \"checkpoint_ref\": \"" + checkpointRef + "\"\n}\n")
		if err := os.WriteFile(configPath, cfg, 0o600); err != nil {
			return fmt.Errorf("write %s: %w", configPath, err)
		}
	}
	ignore := "sessions/\narchive/\n"
	if err := os.WriteFile(filepath.Join(root, traceDir, ".gitignore"), []byte(ignore), 0o600); err != nil {
		return fmt.Errorf("write .trace/.gitignore: %w", err)
	}
	gitkeep := filepath.Join(root, traceDir, "commits", ".gitkeep")
	if _, err := os.Stat(gitkeep); errors.Is(err, os.ErrNotExist) {
		if err := os.WriteFile(gitkeep, nil, 0o600); err != nil {
			return fmt.Errorf("write .trace/commits/.gitkeep: %w", err)
		}
	}
	return nil
}

func enableTrace(root string, w io.Writer) error {
	if err := initTrace(root); err != nil {
		return err
	}
	if err := installGitHook(root); err != nil {
		return err
	}
	if err := installCodexHooks(root); err != nil {
		return err
	}
	if err := installClaudeHooks(root); err != nil {
		return err
	}
	if err := installOpenCodePlugin(root); err != nil {
		return err
	}
	fmt.Fprintln(w, "trace enabled")
	for _, runtime := range []string{"codex", "claude", "opencode"} {
		if _, err := exec.LookPath(runtime); err != nil {
			fmt.Fprintf(w, "%s not found in PATH; rich %s capture requires the user-installed runtime, commit/diff fallback remains active\n", runtime, runtime)
		}
	}
	return nil
}

func installGitHook(root string) error {
	gitDir, err := command(root, "git", "rev-parse", "--git-common-dir")
	if err != nil {
		return fmt.Errorf("resolve git dir: %w", err)
	}
	gitDir = strings.TrimSpace(gitDir)
	if !filepath.IsAbs(gitDir) {
		gitDir = filepath.Join(root, gitDir)
	}
	hooksDir := filepath.Join(gitDir, "hooks")
	if err := os.MkdirAll(hooksDir, 0o750); err != nil {
		return fmt.Errorf("create hooks dir: %w", err)
	}
	body := "#!/bin/sh\ntrace hooks git post-commit >/dev/null 2>&1 || true\n"
	if err := os.WriteFile(filepath.Join(hooksDir, "post-commit"), []byte(body), 0o755); err != nil {
		return fmt.Errorf("write post-commit hook: %w", err)
	}
	return nil
}

type hookFile struct {
	Hooks map[string][]hookMatcher `json:"hooks"`
}

type hookMatcher struct {
	Matcher *string       `json:"matcher"`
	Hooks   []hookCommand `json:"hooks"`
}

type hookCommand struct {
	Type    string `json:"type"`
	Command string `json:"command"`
	Timeout int    `json:"timeout,omitempty"`
}

func installCodexHooks(root string) error {
	path := filepath.Join(root, ".codex", "hooks.json")
	top := readJSONObject(path)
	var hooks map[string][]hookMatcher
	if raw, ok := top["hooks"]; ok {
		_ = json.Unmarshal(raw, &hooks)
	}
	if hooks == nil {
		hooks = map[string][]hookMatcher{}
	}
	for _, item := range []struct {
		event string
		name  string
	}{
		{"SessionStart", "session-start"},
		{"UserPromptSubmit", "user-prompt-submit"},
		{"Stop", "stop"},
		{"PostToolUse", "post-tool-use"},
	} {
		cmd := "trace hooks codex " + item.name
		hooks[item.event] = addCommandHook(hooks[item.event], nil, cmd, 30)
	}
	rawHooks, err := json.Marshal(hooks)
	if err != nil {
		return fmt.Errorf("marshal Codex hooks: %w", err)
	}
	top["hooks"] = rawHooks
	if err := writeJSON(path, top); err != nil {
		return err
	}
	return enableCodexFeature(root)
}

func enableCodexFeature(root string) error {
	path := filepath.Join(root, ".codex", "config.toml")
	data, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read Codex config: %w", err)
	}
	if strings.Contains(string(data), "codex_hooks") {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("create .codex: %w", err)
	}
	next := string(data)
	if next != "" && !strings.HasSuffix(next, "\n") {
		next += "\n"
	}
	next += "\n[features]\ncodex_hooks = true\n"
	return os.WriteFile(path, []byte(next), 0o600)
}

type claudeSettings struct {
	Hooks       map[string][]hookMatcher `json:"hooks,omitempty"`
	Permissions map[string][]string      `json:"permissions,omitempty"`
}

func installClaudeHooks(root string) error {
	path := filepath.Join(root, ".claude", "settings.json")
	top := readJSONObject(path)
	var hooks map[string][]hookMatcher
	if raw, ok := top["hooks"]; ok {
		_ = json.Unmarshal(raw, &hooks)
	}
	if hooks == nil {
		hooks = map[string][]hookMatcher{}
	}
	empty := ""
	for _, item := range []struct {
		event   string
		matcher *string
		name    string
	}{
		{"SessionStart", &empty, "session-start"},
		{"SessionEnd", &empty, "session-end"},
		{"UserPromptSubmit", &empty, "user-prompt-submit"},
		{"Stop", &empty, "stop"},
	} {
		hooks[item.event] = addCommandHook(hooks[item.event], item.matcher, "trace hooks claude-code "+item.name, 0)
	}
	var permissions map[string][]string
	if raw, ok := top["permissions"]; ok {
		_ = json.Unmarshal(raw, &permissions)
	}
	if permissions == nil {
		permissions = map[string][]string{}
	}
	permissions["deny"] = appendMissing(permissions["deny"], "Read(./.trace/sessions/**)")
	rawHooks, err := json.Marshal(hooks)
	if err != nil {
		return fmt.Errorf("marshal Claude hooks: %w", err)
	}
	rawPermissions, err := json.Marshal(permissions)
	if err != nil {
		return fmt.Errorf("marshal Claude permissions: %w", err)
	}
	top["hooks"] = rawHooks
	top["permissions"] = rawPermissions
	return writeJSON(path, top)
}

func installOpenCodePlugin(root string) error {
	path := filepath.Join(root, ".opencode", "plugins", "trace.ts")
	content := strings.ReplaceAll(openCodePlugin, "__TRACE_CMD__", "trace")
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("create OpenCode plugin dir: %w", err)
	}
	return os.WriteFile(path, []byte(content), 0o644)
}

func addCommandHook(groups []hookMatcher, matcher *string, command string, timeout int) []hookMatcher {
	for i := range groups {
		if matcherEqual(groups[i].Matcher, matcher) {
			for _, h := range groups[i].Hooks {
				if h.Command == command {
					return groups
				}
			}
			groups[i].Hooks = append(groups[i].Hooks, hookCommand{Type: "command", Command: command, Timeout: timeout})
			return groups
		}
	}
	return append(groups, hookMatcher{
		Matcher: matcher,
		Hooks:   []hookCommand{{Type: "command", Command: command, Timeout: timeout}},
	})
}

func matcherEqual(a, b *string) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

func readJSON(path string, v any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, v)
}

func readJSONObject(path string) map[string]json.RawMessage {
	data, err := os.ReadFile(path)
	if err != nil {
		return map[string]json.RawMessage{}
	}
	var top map[string]json.RawMessage
	if err := json.Unmarshal(data, &top); err != nil || top == nil {
		return map[string]json.RawMessage{}
	}
	return top
}

func writeJSON(path string, v any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("create %s: %w", filepath.Dir(path), err)
	}
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal %s: %w", path, err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

func appendMissing(items []string, value string) []string {
	for _, item := range items {
		if item == value {
			return items
		}
	}
	return append(items, value)
}

const openCodePlugin = `// Trace CLI plugin for OpenCode.
// Auto-generated by trace enable.
// Hooks call: trace hooks opencode session-start, trace hooks opencode turn-start, trace hooks opencode turn-end, trace hooks opencode session-end.
import type { Plugin } from "@opencode-ai/plugin"

export const TracePlugin: Plugin = async ({ directory }) => {
  const TRACE_CMD = "__TRACE_CMD__"
  const seenUserMessages = new Set<string>()
  let currentSessionID: string | null = null
  let currentModel: string | null = null
  const messageStore = new Map<string, any>()

  function hookCmd(name: string): string[] {
    return ["sh", "-c", TRACE_CMD + " hooks opencode " + name]
  }

  async function callHook(name: string, payload: Record<string, unknown>) {
    try {
      const proc = Bun.spawn(hookCmd(name), {
        cwd: directory,
        stdin: new Blob([JSON.stringify(payload) + "\n"]),
        stdout: "ignore",
        stderr: "ignore",
      })
      await proc.exited
    } catch {}
  }

  function callHookSync(name: string, payload: Record<string, unknown>) {
    try {
      Bun.spawnSync(hookCmd(name), {
        cwd: directory,
        stdin: new TextEncoder().encode(JSON.stringify(payload) + "\n"),
        stdout: "ignore",
        stderr: "ignore",
      })
    } catch {}
  }

  return {
    event: async ({ event }) => {
      try {
        switch (event.type) {
          case "session.created": {
            const session = (event as any).properties?.info
            if (!session?.id) break
            currentSessionID = session.id
            seenUserMessages.clear()
            messageStore.clear()
            await callHook("session-start", { session_id: session.id })
            break
          }
          case "message.updated": {
            const msg = (event as any).properties?.info
            if (!msg) break
            messageStore.set(msg.id, msg)
            if (msg.role === "assistant" && msg.modelID) currentModel = msg.modelID
            break
          }
          case "message.part.updated": {
            const part = (event as any).properties?.part
            const msg = part?.messageID ? messageStore.get(part.messageID) : null
            if (msg?.role === "user" && part.type === "text" && !seenUserMessages.has(msg.id)) {
              seenUserMessages.add(msg.id)
              const sessionID = msg.sessionID ?? currentSessionID
              if (sessionID) await callHook("turn-start", { session_id: sessionID, prompt: part.text ?? "", model: currentModel ?? "" })
            }
            break
          }
          case "session.status": {
            const props = (event as any).properties
            if (props?.status?.type !== "idle") break
            const sessionID = props?.sessionID ?? currentSessionID
            if (sessionID) callHookSync("turn-end", { session_id: sessionID, model: currentModel ?? "" })
            break
          }
          case "session.deleted":
          case "server.instance.disposed": {
            if (!currentSessionID) break
            const sessionID = currentSessionID
            currentSessionID = null
            callHookSync("session-end", { session_id: sessionID })
            break
          }
        }
      } catch {}
    },
  }
}
`

type eventRecord struct {
	Agent          string          `json:"agent"`
	Event          string          `json:"event"`
	SessionID      string          `json:"session_id"`
	TranscriptPath string          `json:"transcript_path,omitempty"`
	Timestamp      string          `json:"timestamp"`
	Payload        json.RawMessage `json:"payload"`
}

func captureAgentHook(root string, agent string, event string, payload []byte) error {
	sessionID, transcriptPath := hookIDs(payload)
	if sessionID == "" {
		sessionID = "unknown"
	}
	record := eventRecord{
		Agent:          agent,
		Event:          event,
		SessionID:      sessionID,
		TranscriptPath: transcriptPath,
		Timestamp:      time.Now().UTC().Format(time.RFC3339Nano),
		Payload:        json.RawMessage(bytes.TrimSpace(payload)),
	}
	if len(record.Payload) == 0 {
		record.Payload = json.RawMessage(`{}`)
	}
	dir := filepath.Join(root, traceDir, "sessions", safeName(agent))
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return fmt.Errorf("create session dir: %w", err)
	}
	line, err := json.Marshal(record)
	if err != nil {
		return fmt.Errorf("marshal hook record: %w", err)
	}
	path := filepath.Join(dir, safeName(sessionID)+".jsonl")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return fmt.Errorf("open session log: %w", err)
	}
	defer f.Close()
	if _, err := f.Write(append(line, '\n')); err != nil {
		return fmt.Errorf("write session log: %w", err)
	}
	return nil
}

func hookIDs(payload []byte) (string, string) {
	var raw map[string]any
	if err := json.Unmarshal(payload, &raw); err != nil {
		return "", ""
	}
	sessionID := stringField(raw, "session_id")
	if sessionID == "" {
		sessionID = stringField(raw, "sessionID")
	}
	transcriptPath := stringField(raw, "transcript_path")
	if transcriptPath == "" {
		transcriptPath = stringField(raw, "transcriptPath")
	}
	return sessionID, transcriptPath
}

func stringField(raw map[string]any, key string) string {
	v, ok := raw[key]
	if !ok {
		return ""
	}
	s, _ := v.(string)
	return s
}

func safeName(value string) string {
	var b strings.Builder
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' || r == '.' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	if b.Len() == 0 {
		return "unknown"
	}
	return b.String()
}

type checkpointRecord struct {
	ID          string              `json:"id"`
	Commit      string              `json:"commit"`
	Message     string              `json:"message"`
	CreatedAt   string              `json:"created_at"`
	Checkpoint  string              `json:"checkpoint_ref"`
	Changed     []string            `json:"changed_files"`
	Diff        string              `json:"diff"`
	Sessions    []sessionCheckpoint `json:"sessions"`
	Transcripts []transcriptCapture `json:"transcripts,omitempty"`
}

type sessionCheckpoint struct {
	Agent string        `json:"agent"`
	Path  string        `json:"path"`
	Lines []eventRecord `json:"lines"`
}

type transcriptCapture struct {
	Path    string `json:"path"`
	Content string `json:"content"`
}

func commitTrace(root string) (*checkpointRecord, error) {
	if err := initTrace(root); err != nil {
		return nil, err
	}
	commit, err := command(root, "git", "rev-parse", "HEAD")
	if err != nil {
		return nil, fmt.Errorf("resolve HEAD: %w", err)
	}
	commit = strings.TrimSpace(commit)
	message, err := command(root, "git", "log", "-1", "--format=%B", commit)
	if err != nil {
		return nil, fmt.Errorf("read commit message: %w", err)
	}
	changed, err := changedFiles(root, commit)
	if err != nil {
		return nil, err
	}
	diff, err := command(root, "git", "show", "--format=", "--find-renames", commit)
	if err != nil {
		return nil, fmt.Errorf("read commit diff: %w", err)
	}
	sessions, transcripts, err := collectSessions(root)
	if err != nil {
		return nil, err
	}
	id := checkpointID(commit, message, sessions)
	record := checkpointRecord{
		ID:          id,
		Commit:      commit,
		Message:     strings.TrimSpace(message),
		CreatedAt:   time.Now().UTC().Format(time.RFC3339Nano),
		Checkpoint:  checkpointRef + ":" + id + "/checkpoint.json",
		Changed:     changed,
		Diff:        redactText(diff),
		Sessions:    sessions,
		Transcripts: transcripts,
	}
	if err := writeCheckpoint(root, record); err != nil {
		return nil, err
	}
	if err := writeMemory(root, record); err != nil {
		return nil, err
	}
	if len(sessions) > 0 {
		_ = archiveSessions(root, commit)
	}
	return &record, nil
}

func checkpointID(commit string, message string, sessions []sessionCheckpoint) string {
	h := sha256.New()
	h.Write([]byte(commit))
	h.Write([]byte(message))
	for _, session := range sessions {
		h.Write([]byte(session.Path))
	}
	return hex.EncodeToString(h.Sum(nil))[:16]
}

func changedFiles(root string, commit string) ([]string, error) {
	out, err := command(root, "git", "diff-tree", "--no-commit-id", "--name-only", "-r", commit)
	if err != nil {
		return nil, fmt.Errorf("read changed files: %w", err)
	}
	var files []string
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			files = append(files, line)
		}
	}
	sort.Strings(files)
	return files, nil
}

func collectSessions(root string) ([]sessionCheckpoint, []transcriptCapture, error) {
	base := filepath.Join(root, traceDir, "sessions")
	var sessions []sessionCheckpoint
	transcriptSeen := map[string]bool{}
	var transcripts []transcriptCapture
	err := filepath.WalkDir(base, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".jsonl") {
			return err
		}
		lines, err := readSessionLines(path)
		if err != nil {
			return err
		}
		if len(lines) == 0 {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		session := sessionCheckpoint{Agent: lines[0].Agent, Path: filepath.ToSlash(rel), Lines: lines}
		sessions = append(sessions, session)
		for _, line := range lines {
			if line.TranscriptPath == "" || transcriptSeen[line.TranscriptPath] {
				continue
			}
			transcriptSeen[line.TranscriptPath] = true
			data, err := os.ReadFile(line.TranscriptPath)
			if err == nil {
				transcripts = append(transcripts, transcriptCapture{Path: line.TranscriptPath, Content: redactText(string(data))})
			}
		}
		return nil
	})
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, nil, fmt.Errorf("collect sessions: %w", err)
	}
	sort.Slice(sessions, func(i, j int) bool { return sessions[i].Path < sessions[j].Path })
	return sessions, transcripts, nil
}

func readSessionLines(path string) ([]eventRecord, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read session %s: %w", path, err)
	}
	var records []eventRecord
	for _, raw := range bytes.Split(data, []byte("\n")) {
		raw = bytes.TrimSpace(raw)
		if len(raw) == 0 {
			continue
		}
		var record eventRecord
		if err := json.Unmarshal(raw, &record); err != nil {
			return nil, fmt.Errorf("parse session %s: %w", path, err)
		}
		record.Payload = json.RawMessage(redactText(string(record.Payload)))
		records = append(records, record)
	}
	return records, nil
}

var secretLine = regexp.MustCompile(`(?i)(api[_-]?key|token|password|secret|authorization)(["'\s:=]+)([^"',\s}]+)`)

func redactText(value string) string {
	return secretLine.ReplaceAllString(value, "$1$2[REDACTED]")
}

func writeCheckpoint(root string, record checkpointRecord) error {
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal checkpoint: %w", err)
	}
	data = append(data, '\n')
	index, err := os.CreateTemp("", "trace-index-*")
	if err != nil {
		return fmt.Errorf("create temp index: %w", err)
	}
	indexPath := index.Name()
	index.Close()
	defer os.Remove(indexPath)
	env := []string{"GIT_INDEX_FILE=" + indexPath}
	if _, err := commandEnv(root, env, nil, "git", "read-tree", "--empty"); err != nil {
		return fmt.Errorf("prepare checkpoint index: %w", err)
	}
	parent, hasParent := currentCheckpointCommit(root)
	if hasParent {
		if _, err := commandEnv(root, env, nil, "git", "read-tree", checkpointRef); err != nil {
			return fmt.Errorf("read checkpoint ref: %w", err)
		}
	}
	blob, err := commandEnv(root, env, data, "git", "hash-object", "-w", "--stdin")
	if err != nil {
		return fmt.Errorf("write checkpoint blob: %w", err)
	}
	blob = strings.TrimSpace(blob)
	path := record.ID + "/checkpoint.json"
	if _, err := commandEnv(root, env, nil, "git", "update-index", "--add", "--cacheinfo", "100644,"+blob+","+path); err != nil {
		return fmt.Errorf("stage checkpoint blob: %w", err)
	}
	tree, err := commandEnv(root, env, nil, "git", "write-tree")
	if err != nil {
		return fmt.Errorf("write checkpoint tree: %w", err)
	}
	tree = strings.TrimSpace(tree)
	args := []string{"commit-tree", tree, "-m", "trace checkpoint " + record.ID}
	if hasParent {
		args = append(args, "-p", parent)
	}
	commit, err := commandEnv(root, env, nil, "git", args...)
	if err != nil {
		return fmt.Errorf("commit checkpoint tree: %w", err)
	}
	commit = strings.TrimSpace(commit)
	if _, err := command(root, "git", "update-ref", checkpointRef, commit); err != nil {
		return fmt.Errorf("update checkpoint ref: %w", err)
	}
	return nil
}

func currentCheckpointCommit(root string) (string, bool) {
	out, err := command(root, "git", "rev-parse", "--verify", checkpointRef+"^{commit}")
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(out), true
}

func writeMemory(root string, record checkpointRecord) error {
	path := filepath.Join(root, traceDir, "commits", record.Commit+".md")
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("create commit memory dir: %w", err)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n", shortSHA(record.Commit))
	fmt.Fprintf(&b, "Commit: `%s`\n\n", record.Commit)
	fmt.Fprintf(&b, "Checkpoint: `%s`\n\n", record.Checkpoint)
	subject := firstLine(record.Message)
	if subject == "" {
		subject = "(no commit message)"
	}
	fmt.Fprintf(&b, "Summary: %s\n\n", subject)
	if len(record.Sessions) == 0 {
		fmt.Fprintln(&b, "Source: commit message and diff fallback; no agent session was captured.")
	} else {
		var agents []string
		for _, session := range record.Sessions {
			agents = append(agents, session.Agent)
		}
		fmt.Fprintf(&b, "Source: captured agent sessions (%s).\n", strings.Join(unique(agents), ", "))
	}
	if len(record.Changed) > 0 {
		fmt.Fprintln(&b, "\nChanged files:")
		for _, file := range record.Changed {
			fmt.Fprintf(&b, "- `%s`\n", file)
		}
	}
	return os.WriteFile(path, []byte(b.String()), 0o600)
}

func archiveSessions(root string, commit string) error {
	src := filepath.Join(root, traceDir, "sessions")
	dst := filepath.Join(root, traceDir, "archive", commit)
	if err := os.MkdirAll(filepath.Dir(dst), 0o750); err != nil {
		return err
	}
	if err := os.RemoveAll(dst); err != nil {
		return err
	}
	if err := os.Rename(src, dst); err != nil {
		return err
	}
	return os.MkdirAll(src, 0o750)
}

func shortSHA(sha string) string {
	if len(sha) < 12 {
		return sha
	}
	return sha[:12]
}

func firstLine(value string) string {
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			return line
		}
	}
	return ""
}

func unique(values []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, value := range values {
		if !seen[value] {
			seen[value] = true
			out = append(out, value)
		}
	}
	sort.Strings(out)
	return out
}

func showMemory(commit string, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	sha, err := command(root, "git", "rev-parse", commit)
	if err != nil {
		return fmt.Errorf("resolve commit %q: %w", commit, err)
	}
	sha = strings.TrimSpace(sha)
	data, err := os.ReadFile(filepath.Join(root, traceDir, "commits", sha+".md"))
	if err != nil {
		return fmt.Errorf("memory not found for %s", commit)
	}
	_, err = w.Write(data)
	return err
}

func recallMemory(query string, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" {
		return errors.New("recall query cannot be empty")
	}
	dir := filepath.Join(root, traceDir, "commits")
	var matches []string
	err = filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".md") {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		content := strings.ToLower(string(data))
		if strings.Contains(content, query) {
			rel, _ := filepath.Rel(root, path)
			matches = append(matches, filepath.ToSlash(rel)+": "+firstLine(string(data)))
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("recall memory: %w", err)
	}
	sort.Strings(matches)
	if len(matches) == 0 {
		fmt.Fprintln(w, "no matching memory")
		return nil
	}
	for _, match := range matches {
		fmt.Fprintln(w, match)
	}
	return nil
}
