package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

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
	if agent == "claude-code" && event == "stop" && transcriptPath != "" {
		waitForClaudeTranscriptFlush(transcriptPath, time.Now())
	}
	if agent == "opencode" && sessionID != "unknown" {
		transcriptPath = openCodeTranscriptPath(root, sessionID)
		if shouldExportOpenCode(event) {
			_ = exportOpenCodeTranscript(root, sessionID)
		}
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

func shouldExportOpenCode(event string) bool {
	return event == "turn-end" || event == "session-end"
}

func openCodeTranscriptPath(root string, sessionID string) string {
	return filepath.Join(root, traceDir, "tmp", "opencode", safeName(sessionID)+".json")
}

func exportOpenCodeTranscript(root string, sessionID string) error {
	outPath := openCodeTranscriptPath(root, sessionID)
	if os.Getenv("TRACE_TEST_OPENCODE_MOCK_EXPORT") != "" {
		if _, err := os.Stat(outPath); err == nil {
			return nil
		}
		return fmt.Errorf("mock OpenCode export not found: %s", outPath)
	}
	if err := os.MkdirAll(filepath.Dir(outPath), 0o750); err != nil {
		return fmt.Errorf("create OpenCode export dir: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	file, err := os.OpenFile(outPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return fmt.Errorf("create OpenCode export file: %w", err)
	}
	defer file.Close()
	cmd := exec.CommandContext(ctx, "opencode", "export", sessionID)
	cmd.Stdout = file
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		_ = os.Remove(outPath)
		if ctx.Err() == context.DeadlineExceeded {
			return errors.New("opencode export timed out after 30s")
		}
		return fmt.Errorf("opencode export failed: %w: %s", err, strings.TrimSpace(stderr.String()))
	}
	data, err := os.ReadFile(outPath)
	if err != nil {
		return fmt.Errorf("read OpenCode export: %w", err)
	}
	if !json.Valid(data) {
		_ = os.Remove(outPath)
		return fmt.Errorf("opencode export returned invalid JSON")
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
