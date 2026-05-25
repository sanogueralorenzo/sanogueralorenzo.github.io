package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

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
	Agent     string              `json:"agent"`
	Path      string              `json:"path"`
	Content   string              `json:"content"`
	Messages  []transcriptMessage `json:"messages,omitempty"`
	ToolCalls []transcriptTool    `json:"tool_calls,omitempty"`
	Files     []string            `json:"files,omitempty"`
}

type transcriptMessage struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

type transcriptTool struct {
	Name  string   `json:"name"`
	Files []string `json:"files,omitempty"`
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
		prepareSessionTranscripts(root, lines)
		session := sessionCheckpoint{Agent: lines[0].Agent, Path: filepath.ToSlash(rel), Lines: lines}
		sessions = append(sessions, session)
		for _, line := range lines {
			if line.TranscriptPath == "" || transcriptSeen[line.TranscriptPath] {
				continue
			}
			transcriptSeen[line.TranscriptPath] = true
			data, err := os.ReadFile(line.TranscriptPath)
			if err == nil {
				capture := transcriptCapture{
					Agent:   line.Agent,
					Path:    line.TranscriptPath,
					Content: redactText(string(data)),
				}
				if line.Agent == "codex" {
					capture.Messages, capture.ToolCalls, capture.Files = parseCodexTranscript(data)
				}
				transcripts = append(transcripts, capture)
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

func prepareSessionTranscripts(root string, lines []eventRecord) {
	for _, line := range lines {
		switch line.Agent {
		case "opencode":
			if line.SessionID != "" && shouldExportOpenCode(line.Event) {
				_ = exportOpenCodeTranscript(root, line.SessionID)
			}
		}
	}
}

func waitForClaudeTranscriptFlush(path string, started time.Time) {
	const (
		maxWait        = 3 * time.Second
		pollInterval   = 50 * time.Millisecond
		staleThreshold = 2 * time.Minute
	)
	info, err := os.Stat(path)
	if err != nil || time.Since(info.ModTime()) > staleThreshold {
		return
	}
	deadline := time.Now().Add(maxWait)
	for time.Now().Before(deadline) {
		if hasClaudeStopSentinel(path, started) {
			return
		}
		time.Sleep(pollInterval)
	}
}

func hasClaudeStopSentinel(path string, started time.Time) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	if len(data) > 4096 {
		data = data[len(data)-4096:]
	}
	for _, raw := range strings.Split(string(data), "\n") {
		if !strings.Contains(raw, "hooks claude-code stop") {
			continue
		}
		var entry struct {
			Timestamp string `json:"timestamp"`
		}
		if json.Unmarshal([]byte(strings.TrimSpace(raw)), &entry) != nil || entry.Timestamp == "" {
			continue
		}
		ts, err := time.Parse(time.RFC3339Nano, entry.Timestamp)
		if err != nil {
			ts, err = time.Parse(time.RFC3339, entry.Timestamp)
			if err != nil {
				continue
			}
		}
		if ts.After(started.Add(-2*time.Second)) && ts.Before(started.Add(2*time.Second)) {
			return true
		}
	}
	return false
}

func parseCodexTranscript(data []byte) ([]transcriptMessage, []transcriptTool, []string) {
	var messages []transcriptMessage
	var tools []transcriptTool
	filesSeen := map[string]bool{}
	for _, raw := range bytes.Split(data, []byte("\n")) {
		raw = bytes.TrimSpace(raw)
		if len(raw) == 0 {
			continue
		}
		var line struct {
			Type    string          `json:"type"`
			Payload json.RawMessage `json:"payload"`
		}
		if json.Unmarshal(raw, &line) != nil || line.Type != "response_item" {
			continue
		}
		var payload struct {
			Type    string          `json:"type"`
			Role    string          `json:"role,omitempty"`
			Name    string          `json:"name,omitempty"`
			Input   string          `json:"input,omitempty"`
			Content json.RawMessage `json:"content,omitempty"`
		}
		if json.Unmarshal(line.Payload, &payload) != nil {
			continue
		}
		switch payload.Type {
		case "message":
			text := codexContentText(payload.Content)
			if payload.Role != "" && text != "" {
				messages = append(messages, transcriptMessage{Role: payload.Role, Text: redactText(text)})
			}
		case "custom_tool_call":
			tool := transcriptTool{Name: payload.Name}
			if payload.Name == "apply_patch" {
				tool.Files = codexApplyPatchFiles(payload.Input)
				for _, file := range tool.Files {
					filesSeen[file] = true
				}
			}
			tools = append(tools, tool)
		}
	}
	var files []string
	for file := range filesSeen {
		files = append(files, file)
	}
	sort.Strings(files)
	return messages, tools, files
}

func codexContentText(raw json.RawMessage) string {
	var blocks []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	if json.Unmarshal(raw, &blocks) == nil {
		var parts []string
		for _, block := range blocks {
			if block.Text != "" {
				parts = append(parts, block.Text)
			}
		}
		return strings.Join(parts, "\n")
	}
	var text string
	if json.Unmarshal(raw, &text) == nil {
		return text
	}
	return ""
}

var codexPatchFile = regexp.MustCompile(`\*\*\* (Add|Update|Delete) File: (.+)`)

func codexApplyPatchFiles(input string) []string {
	seen := map[string]bool{}
	for _, line := range strings.Split(input, "\n") {
		match := codexPatchFile.FindStringSubmatch(line)
		if len(match) == 3 {
			file := strings.TrimSpace(match[2])
			if file != "" {
				seen[file] = true
			}
		}
	}
	var files []string
	for file := range seen {
		files = append(files, file)
	}
	sort.Strings(files)
	return files
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
	return writeRefFile(root, checkpointRef, record.ID+"/checkpoint.json", data, "trace checkpoint "+record.ID)
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
