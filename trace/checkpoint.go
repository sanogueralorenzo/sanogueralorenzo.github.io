package main

import (
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
