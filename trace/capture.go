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
	Source         string          `json:"source"`
	Event          string          `json:"event"`
	SessionID      string          `json:"session_id"`
	TranscriptPath string          `json:"transcript_path,omitempty"`
	Timestamp      string          `json:"timestamp"`
	Payload        json.RawMessage `json:"payload"`
}

var exportOpenCodeTranscriptFn = exportOpenCodeTranscript

func captureSessionEvent(root string, source string, event string, payload []byte) error {
	if err := initTrace(root); err != nil {
		return err
	}
	source = strings.TrimSpace(source)
	event = strings.TrimSpace(event)
	if source == "" || event == "" {
		return errors.New("source and event are required")
	}
	sessionID, transcriptPath := hookIDs(payload)
	if sessionID == "" {
		return errors.New("hook payload requires session_id")
	}
	if source == "claude-code" && event == "turn-end" && transcriptPath != "" {
		waitForClaudeTranscriptFlush(transcriptPath, time.Now())
	}
	if source == "opencode" {
		path, err := openCodeTranscriptPath(root, sessionID)
		if err != nil {
			return err
		}
		transcriptPath = path
		if shouldExportOpenCode(event) {
			_ = exportOpenCodeTranscriptFn(root, sessionID)
		}
	}
	record := eventRecord{
		Source:         source,
		Event:          event,
		SessionID:      sessionID,
		TranscriptPath: transcriptPath,
		Timestamp:      time.Now().UTC().Format(time.RFC3339Nano),
		Payload:        json.RawMessage(bytes.TrimSpace(payload)),
	}
	if len(record.Payload) == 0 {
		record.Payload = json.RawMessage(`{}`)
	}
	dir, err := traceDataPath(root, "sessions", safeName(source))
	if err != nil {
		return err
	}
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
	if _, err := f.Write(append(line, '\n')); err != nil {
		_ = f.Close()
		return fmt.Errorf("write session log: %w", err)
	}
	if err := f.Close(); err != nil {
		return fmt.Errorf("close session log: %w", err)
	}
	return persistCapturedSession(root, source, sessionID)
}

func prepareTranscriptForCheckpoint(root string, events []eventRecord) {
	if len(events) == 0 || events[0].Source != "opencode" || events[len(events)-1].Event == "session-end" {
		return
	}
	_ = exportOpenCodeTranscriptFn(root, events[0].SessionID)
}

func shouldExportOpenCode(event string) bool {
	return event == "turn-end" || event == "session-end"
}

func openCodeTranscriptPath(root string, sessionID string) (string, error) {
	return traceDataPath(root, "tmp", "opencode", safeName(sessionID)+".json")
}

func exportOpenCodeTranscript(root string, sessionID string) error {
	outPath, err := openCodeTranscriptPath(root, sessionID)
	if err != nil {
		return err
	}
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

func waitForClaudeTranscriptFlush(path string, started time.Time) {
	const (
		maxWait        = 3 * time.Second
		pollInterval   = 50 * time.Millisecond
		quietWindow    = 500 * time.Millisecond
		staleThreshold = 2 * time.Minute
	)
	info, err := os.Stat(path)
	if err != nil || time.Since(info.ModTime()) > staleThreshold {
		return
	}
	deadline := time.Now().Add(maxWait)
	lastSize := int64(-1)
	var stableSince time.Time
	for time.Now().Before(deadline) {
		if hasClaudeStopSentinel(path, started) {
			return
		}
		if current, statErr := os.Stat(path); statErr == nil {
			if current.Size() != lastSize {
				lastSize = current.Size()
				stableSince = time.Now()
			} else if time.Since(stableSince) >= quietWindow {
				return
			}
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
		if !strings.Contains(raw, "trace ingest claude-code turn-end") {
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
