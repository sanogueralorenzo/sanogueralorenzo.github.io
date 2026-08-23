package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

const schemaVersion = 2

type conversationMessage struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

type repositoryMetadata struct {
	Name   string `json:"name"`
	Remote string `json:"remote,omitempty"`
}

type eventKind struct {
	Name  string `json:"name"`
	Count int    `json:"count"`
}

type commitMetadata struct {
	SHA         string   `json:"sha"`
	Subject     string   `json:"subject"`
	Branch      string   `json:"branch"`
	CommittedAt string   `json:"committed_at"`
	Files       []string `json:"files,omitempty"`
}

type sessionCommit struct {
	Commit         commitMetadata `json:"commit"`
	LinkedAt       string         `json:"linked_at"`
	MessageFrom    int            `json:"message_from,omitempty"`
	MessageThrough int            `json:"message_through,omitempty"`
	EventFrom      int            `json:"event_from"`
	EventThrough   int            `json:"event_through"`
}

type sessionRecord struct {
	SchemaVersion               int                   `json:"schema_version"`
	ID                          string                `json:"session_id"`
	Source                      string                `json:"source"`
	Repository                  repositoryMetadata    `json:"repository"`
	Branch                      string                `json:"branch"`
	StartedAt                   string                `json:"started_at"`
	UpdatedAt                   string                `json:"updated_at"`
	Models                      []string              `json:"models,omitempty"`
	TranscriptStatus            string                `json:"transcript_status"`
	TranscriptUnavailableReason string                `json:"transcript_unavailable_reason,omitempty"`
	MessageCount                int                   `json:"message_count"`
	EventCount                  int                   `json:"event_count"`
	EventKinds                  []eventKind           `json:"event_kinds"`
	Commits                     []sessionCommit       `json:"commits"`
	Messages                    []conversationMessage `json:"messages,omitempty"`
	Events                      []eventRecord         `json:"events"`
}

type sessionPointer struct {
	SessionID string `json:"session_id"`
	Source    string `json:"source"`
}

type commitConversation struct {
	SchemaVersion int              `json:"schema_version"`
	Commit        commitMetadata   `json:"commit"`
	LinkedAt      string           `json:"linked_at"`
	Sessions      []sessionPointer `json:"sessions"`
}

type sessionCursor struct {
	Messages int `json:"messages"`
	Events   int `json:"events"`
}

type traceState struct {
	Sessions map[string]sessionCursor `json:"sessions"`
}

type commitSessionView struct {
	SessionID      string                `json:"session_id"`
	Source         string                `json:"source"`
	Models         []string              `json:"models,omitempty"`
	StartedAt      string                `json:"started_at"`
	UpdatedAt      string                `json:"updated_at"`
	MessageFrom    int                   `json:"message_from,omitempty"`
	MessageThrough int                   `json:"message_through,omitempty"`
	EventFrom      int                   `json:"event_from"`
	EventThrough   int                   `json:"event_through"`
	Messages       []conversationMessage `json:"messages,omitempty"`
	Events         []eventRecord         `json:"events,omitempty"`
}

type commitView struct {
	SchemaVersion int                 `json:"schema_version"`
	Commit        commitMetadata      `json:"commit"`
	LinkedAt      string              `json:"linked_at"`
	Sessions      []commitSessionView `json:"sessions"`
}

type sessionSummary struct {
	SchemaVersion    int                `json:"schema_version"`
	SessionID        string             `json:"session_id"`
	Source           string             `json:"source"`
	Repository       repositoryMetadata `json:"repository"`
	Branch           string             `json:"branch"`
	StartedAt        string             `json:"started_at"`
	UpdatedAt        string             `json:"updated_at"`
	Models           []string           `json:"models,omitempty"`
	TranscriptStatus string             `json:"transcript_status"`
	MessageCount     int                `json:"message_count"`
	EventCount       int                `json:"event_count"`
	CommitCount      int                `json:"commit_count"`
}

func linkCommitSessions(root string) (*commitConversation, error) {
	if err := initTrace(root); err != nil {
		return nil, err
	}
	commit, err := currentCommitMetadata(root)
	if err != nil {
		return nil, err
	}
	records, err := collectSessionRecords(root)
	if err != nil {
		return nil, err
	}
	state, err := readTraceState(root)
	if err != nil {
		return nil, err
	}
	linkedAt := time.Now().UTC().Format(time.RFC3339Nano)
	result := &commitConversation{SchemaVersion: schemaVersion, Commit: commit, LinkedAt: linkedAt}
	for _, current := range records {
		stored, found, err := readSessionRecord(root, current.Source, current.ID)
		if err != nil {
			return nil, err
		}
		if found {
			current = mergeSessionRecords(stored, current)
		}
		key := sessionStateKey(current.Source, current.ID)
		previous := state.Sessions[key]
		if current.MessageCount <= previous.Messages && current.EventCount <= previous.Events {
			continue
		}
		link := sessionCommit{
			Commit:       commit,
			LinkedAt:     linkedAt,
			EventFrom:    previous.Events + 1,
			EventThrough: current.EventCount,
		}
		if current.MessageCount > previous.Messages {
			link.MessageFrom = previous.Messages + 1
			link.MessageThrough = current.MessageCount
		}
		current.Commits = upsertSessionCommit(current.Commits, link)
		if err := writeSessionRecord(root, current); err != nil {
			return nil, err
		}
		result.Sessions = append(result.Sessions, sessionPointer{SessionID: current.ID, Source: current.Source})
		state.Sessions[key] = sessionCursor{Messages: current.MessageCount, Events: current.EventCount}
	}
	if len(result.Sessions) == 0 {
		return result, nil
	}
	if err := writeCommitConversation(root, *result); err != nil {
		return nil, err
	}
	if err := writeTraceState(root, state); err != nil {
		return nil, err
	}
	return result, nil
}

func persistCapturedSession(root string, source string, sessionID string) error {
	path, err := traceDataPath(root, "sessions", safeName(source), safeName(sessionID)+".jsonl")
	if err != nil {
		return err
	}
	events, err := readSessionLines(path)
	if err != nil {
		return err
	}
	current := buildSessionRecord(root, events)
	stored, found, err := readSessionRecord(root, source, sessionID)
	if err != nil {
		return err
	}
	if found {
		current = mergeSessionRecords(stored, current)
	}
	return writeSessionRecord(root, current)
}

func collectSessionRecords(root string) ([]sessionRecord, error) {
	base, err := traceDataPath(root, "sessions")
	if err != nil {
		return nil, err
	}
	var records []sessionRecord
	err = filepath.WalkDir(base, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".jsonl") {
			return nil
		}
		events, err := readSessionLines(path)
		if err != nil {
			return err
		}
		if len(events) > 0 {
			records = append(records, buildSessionRecord(root, events))
		}
		return nil
	})
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("collect sessions: %w", err)
	}
	sort.Slice(records, func(i, j int) bool {
		if records[i].Source == records[j].Source {
			return records[i].ID < records[j].ID
		}
		return records[i].Source < records[j].Source
	})
	return records, nil
}

func buildSessionRecord(root string, events []eventRecord) sessionRecord {
	messages, transcriptStatus, unavailableReason := sessionTranscriptMessages(events)
	durableEvents := redactEventRecords(events)
	record := sessionRecord{
		SchemaVersion:               schemaVersion,
		ID:                          events[0].SessionID,
		Source:                      events[0].Source,
		Repository:                  repositoryFor(root),
		Branch:                      currentBranch(root),
		StartedAt:                   events[0].Timestamp,
		UpdatedAt:                   events[len(events)-1].Timestamp,
		Models:                      modelsFromEvents(events),
		TranscriptStatus:            transcriptStatus,
		TranscriptUnavailableReason: unavailableReason,
		MessageCount:                len(messages),
		EventCount:                  len(events),
		EventKinds:                  summarizeEvents(events),
		Messages:                    messages,
		Events:                      durableEvents,
	}
	return record
}

func mergeSessionRecords(stored sessionRecord, current sessionRecord) sessionRecord {
	current.Messages = mergeMessages(stored.Messages, current.Messages)
	current.MessageCount = len(current.Messages)
	current.Models = uniqueSorted(append(stored.Models, current.Models...))
	current.Commits = stored.Commits
	if current.TranscriptStatus != "captured" && stored.TranscriptStatus == "captured" {
		current.TranscriptStatus = stored.TranscriptStatus
		current.TranscriptUnavailableReason = ""
	}
	if stored.StartedAt != "" {
		current.StartedAt = stored.StartedAt
	}
	return current
}

func mergeMessages(stored []conversationMessage, current []conversationMessage) []conversationMessage {
	if hasMessagePrefix(current, stored) {
		return current
	}
	if hasMessagePrefix(stored, current) {
		return stored
	}
	for overlap := min(len(stored), len(current)); overlap > 0; overlap-- {
		if messagesEqual(stored[len(stored)-overlap:], current[:overlap]) {
			return append(append([]conversationMessage{}, stored...), current[overlap:]...)
		}
	}
	return append(append([]conversationMessage{}, stored...), current...)
}

func hasMessagePrefix(messages []conversationMessage, prefix []conversationMessage) bool {
	return len(messages) >= len(prefix) && messagesEqual(messages[:len(prefix)], prefix)
}

func messagesEqual(a []conversationMessage, b []conversationMessage) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func sessionTranscriptMessages(events []eventRecord) ([]conversationMessage, string, string) {
	hasTranscript := false
	unavailableReason := ""
	for i := len(events) - 1; i >= 0; i-- {
		path := events[i].TranscriptPath
		if path == "" {
			continue
		}
		hasTranscript = true
		data, err := os.ReadFile(path)
		if err != nil {
			unavailableReason = "unreadable"
			continue
		}
		if messages := parseTranscriptMessages(data); len(messages) > 0 {
			return messages, "captured", ""
		}
		if unavailableReason == "" {
			unavailableReason = "empty"
		}
	}
	if hasTranscript {
		return messagesFromEvents(events), "unavailable", unavailableReason
	}
	return messagesFromEvents(events), "not_provided", ""
}

func parseTranscriptMessages(data []byte) []conversationMessage {
	var messages []conversationMessage
	var document any
	if json.Unmarshal(data, &document) == nil {
		collectRoleMessages(document, &messages)
	} else {
		for _, raw := range bytes.Split(data, []byte("\n")) {
			raw = bytes.TrimSpace(raw)
			if len(raw) == 0 || json.Unmarshal(raw, &document) != nil {
				continue
			}
			collectRoleMessages(document, &messages)
		}
	}
	return uniqueMessages(messages)
}

func collectRoleMessages(value any, messages *[]conversationMessage) {
	switch typed := value.(type) {
	case []any:
		for _, item := range typed {
			collectRoleMessages(item, messages)
		}
	case map[string]any:
		role, _ := typed["role"].(string)
		role = strings.ToLower(strings.TrimSpace(role))
		if role == "user" || role == "assistant" {
			text := messageText(typed["content"])
			if text == "" {
				text = messageText(typed["text"])
			}
			if text != "" {
				*messages = append(*messages, conversationMessage{Role: role, Text: redactText(text)})
				return
			}
		}
		for _, child := range typed {
			collectRoleMessages(child, messages)
		}
	}
}

func messageText(value any) string {
	switch typed := value.(type) {
	case string:
		return strings.TrimSpace(typed)
	case []any:
		var parts []string
		for _, item := range typed {
			if text := messageText(item); text != "" {
				parts = append(parts, text)
			}
		}
		return strings.Join(parts, "\n")
	case map[string]any:
		for _, key := range []string{"text", "content", "value"} {
			if text := messageText(typed[key]); text != "" {
				return text
			}
		}
	}
	return ""
}

func messagesFromEvents(events []eventRecord) []conversationMessage {
	var messages []conversationMessage
	for _, event := range events {
		var payload map[string]any
		if json.Unmarshal(event.Payload, &payload) != nil {
			continue
		}
		before := len(messages)
		collectRoleMessages(payload["messages"], &messages)
		if len(messages) > before {
			continue
		}
		if prompt, _ := payload["prompt"].(string); strings.TrimSpace(prompt) != "" {
			messages = append(messages, conversationMessage{Role: "user", Text: redactText(prompt)})
		}
		for _, key := range []string{"response", "output"} {
			if response, _ := payload[key].(string); strings.TrimSpace(response) != "" {
				messages = append(messages, conversationMessage{Role: "assistant", Text: redactText(response)})
			}
		}
	}
	return uniqueMessages(messages)
}

func uniqueMessages(messages []conversationMessage) []conversationMessage {
	var unique []conversationMessage
	for _, message := range messages {
		message.Text = strings.TrimSpace(message.Text)
		if message.Text == "" {
			continue
		}
		if len(unique) > 0 && unique[len(unique)-1] == message {
			continue
		}
		unique = append(unique, message)
	}
	return unique
}

func modelsFromEvents(events []eventRecord) []string {
	var models []string
	for _, event := range events {
		var payload any
		if json.Unmarshal(event.Payload, &payload) == nil {
			collectMetadataValues(payload, map[string]bool{"model": true, "model_id": true, "modelID": true}, &models)
		}
	}
	return uniqueSorted(models)
}

func collectMetadataValues(value any, keys map[string]bool, values *[]string) {
	switch typed := value.(type) {
	case []any:
		for _, item := range typed {
			collectMetadataValues(item, keys, values)
		}
	case map[string]any:
		for key, child := range typed {
			if keys[key] {
				if text, ok := child.(string); ok && strings.TrimSpace(text) != "" {
					*values = append(*values, strings.TrimSpace(text))
				}
			}
			collectMetadataValues(child, keys, values)
		}
	}
}

func summarizeEvents(events []eventRecord) []eventKind {
	counts := map[string]int{}
	for _, event := range events {
		counts[event.Event]++
	}
	names := make([]string, 0, len(counts))
	for name := range counts {
		names = append(names, name)
	}
	sort.Strings(names)
	summary := make([]eventKind, 0, len(names))
	for _, name := range names {
		summary = append(summary, eventKind{Name: name, Count: counts[name]})
	}
	return summary
}

func uniqueSorted(values []string) []string {
	seen := map[string]bool{}
	var unique []string
	for _, value := range values {
		if value != "" && !seen[value] {
			seen[value] = true
			unique = append(unique, value)
		}
	}
	sort.Strings(unique)
	return unique
}

func repositoryFor(root string) repositoryMetadata {
	repository := repositoryMetadata{Name: filepath.Base(root)}
	if remote, err := command(root, "git", "remote", "get-url", "origin"); err == nil {
		repository.Remote = sanitizeRemote(strings.TrimSpace(remote))
	}
	return repository
}

func sanitizeRemote(remote string) string {
	parsed, err := url.Parse(remote)
	if err == nil && parsed.Scheme != "" {
		parsed.User = nil
		return parsed.String()
	}
	return remote
}

func currentBranch(root string) string {
	branch, err := command(root, "git", "branch", "--show-current")
	if err != nil || strings.TrimSpace(branch) == "" {
		return "detached"
	}
	return strings.TrimSpace(branch)
}

func currentCommitMetadata(root string) (commitMetadata, error) {
	out, err := command(root, "git", "show", "-s", "--format=%H%n%s%n%cI", "HEAD")
	if err != nil {
		return commitMetadata{}, fmt.Errorf("read HEAD: %w", err)
	}
	parts := strings.SplitN(strings.TrimSpace(out), "\n", 3)
	if len(parts) != 3 {
		return commitMetadata{}, errors.New("read HEAD: unexpected git output")
	}
	files, err := commitFiles(root, parts[0])
	if err != nil {
		return commitMetadata{}, err
	}
	return commitMetadata{SHA: parts[0], Subject: parts[1], Branch: currentBranch(root), CommittedAt: parts[2], Files: files}, nil
}

func commitFiles(root string, sha string) ([]string, error) {
	out, err := command(root, "git", "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", sha)
	if err != nil {
		return nil, fmt.Errorf("read files for commit %s: %w", sha, err)
	}
	var files []string
	for _, file := range strings.Split(out, "\n") {
		if file = strings.TrimSpace(file); file != "" {
			files = append(files, file)
		}
	}
	sort.Strings(files)
	return files, nil
}

func upsertSessionCommit(commits []sessionCommit, next sessionCommit) []sessionCommit {
	for i := range commits {
		if commits[i].Commit.SHA == next.Commit.SHA {
			commits[i] = next
			return commits
		}
	}
	return append(commits, next)
}

func writeSessionRecord(root string, record sessionRecord) error {
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal session %s: %w", record.ID, err)
	}
	data = append(data, '\n')
	return writeRefFile(root, sessionRefFor(record.Source, record.ID), "session.json", data, "trace session "+record.ID)
}

func sessionRefFor(source string, sessionID string) string {
	key := fmt.Sprintf("%x", sha256.Sum256([]byte(source+"\x00"+sessionID)))
	return sessionRefPrefix + "/" + key[:2] + "/" + key
}

func readSessionRecord(root string, source string, sessionID string) (sessionRecord, bool, error) {
	data, err := command(root, "git", "show", sessionRefFor(source, sessionID)+":session.json")
	if err != nil {
		return sessionRecord{}, false, nil
	}
	var record sessionRecord
	if err := json.Unmarshal([]byte(data), &record); err != nil {
		return sessionRecord{}, false, fmt.Errorf("parse session %s: %w", sessionID, err)
	}
	return record, true, nil
}

func listSessionRecords(root string) ([]sessionRecord, error) {
	out, err := command(root, "git", "for-each-ref", "--format=%(refname)", sessionRefPrefix+"/")
	if err != nil {
		return nil, nil
	}
	var records []sessionRecord
	for _, ref := range strings.Split(out, "\n") {
		ref = strings.TrimSpace(ref)
		if ref == "" {
			continue
		}
		data, err := command(root, "git", "show", ref+":session.json")
		if err != nil {
			return nil, fmt.Errorf("read session at %s: %w", ref, err)
		}
		var record sessionRecord
		if err := json.Unmarshal([]byte(data), &record); err != nil {
			return nil, fmt.Errorf("parse session at %s: %w", ref, err)
		}
		records = append(records, record)
	}
	sort.Slice(records, func(i, j int) bool { return records[i].UpdatedAt > records[j].UpdatedAt })
	return records, nil
}

func findSessionRecord(root string, sessionID string) (sessionRecord, error) {
	records, err := listSessionRecords(root)
	if err != nil {
		return sessionRecord{}, err
	}
	var matches []sessionRecord
	for _, record := range records {
		if record.ID == sessionID {
			matches = append(matches, record)
		}
	}
	if len(matches) == 0 {
		return sessionRecord{}, fmt.Errorf("session %q not found", sessionID)
	}
	if len(matches) > 1 {
		return sessionRecord{}, fmt.Errorf("session %q exists for multiple sources", sessionID)
	}
	return matches[0], nil
}

func writeCommitConversation(root string, record commitConversation) error {
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal commit conversation: %w", err)
	}
	data = append(data, '\n')
	if _, err := commandEnv(root, nil, data, "git", "notes", "--ref="+noteRef, "add", "-f", "-F", "-", record.Commit.SHA); err != nil {
		return fmt.Errorf("link sessions to commit %s: %w", record.Commit.SHA, err)
	}
	return nil
}

func readCommitConversation(root string, revision string) (commitConversation, error) {
	sha, err := command(root, "git", "rev-parse", revision)
	if err != nil {
		return commitConversation{}, fmt.Errorf("resolve commit %q: %w", revision, err)
	}
	sha = strings.TrimSpace(sha)
	data, err := command(root, "git", "notes", "--ref="+noteRef, "show", sha)
	if err != nil {
		return commitConversation{}, fmt.Errorf("no sessions linked to %s", revision)
	}
	var record commitConversation
	if err := json.Unmarshal([]byte(data), &record); err != nil {
		return commitConversation{}, fmt.Errorf("parse session links for %s: %w", revision, err)
	}
	return record, nil
}

func buildCommitView(root string, revision string) (commitView, error) {
	record, err := readCommitConversation(root, revision)
	if err != nil {
		return commitView{}, err
	}
	view := commitView{SchemaVersion: record.SchemaVersion, Commit: record.Commit, LinkedAt: record.LinkedAt}
	for _, pointer := range record.Sessions {
		session, found, err := readSessionRecord(root, pointer.Source, pointer.SessionID)
		if err != nil {
			return commitView{}, err
		}
		if !found {
			return commitView{}, fmt.Errorf("session %q not found", pointer.SessionID)
		}
		link, found := sessionCommitFor(session, record.Commit.SHA)
		if !found {
			return commitView{}, fmt.Errorf("session %q has no range for commit %s", pointer.SessionID, record.Commit.SHA)
		}
		item := commitSessionView{
			SessionID:      session.ID,
			Source:         session.Source,
			Models:         session.Models,
			StartedAt:      session.StartedAt,
			UpdatedAt:      session.UpdatedAt,
			MessageFrom:    link.MessageFrom,
			MessageThrough: link.MessageThrough,
			EventFrom:      link.EventFrom,
			EventThrough:   link.EventThrough,
		}
		if link.MessageFrom > 0 && link.MessageThrough <= len(session.Messages) {
			item.Messages = session.Messages[link.MessageFrom-1 : link.MessageThrough]
		} else if link.EventFrom > 0 && link.EventThrough <= len(session.Events) {
			item.Events = session.Events[link.EventFrom-1 : link.EventThrough]
		}
		view.Sessions = append(view.Sessions, item)
	}
	return view, nil
}

func sessionCommitFor(session sessionRecord, sha string) (sessionCommit, bool) {
	for _, commit := range session.Commits {
		if commit.Commit.SHA == sha {
			return commit, true
		}
	}
	return sessionCommit{}, false
}

func showCommitConversation(revision string, asJSON bool, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	view, err := buildCommitView(root, revision)
	if err != nil {
		return err
	}
	if asJSON {
		return writeJSONOutput(w, view)
	}
	fmt.Fprintf(w, "Commit: %s\nSubject: %s\nBranch: %s\n", view.Commit.SHA, view.Commit.Subject, view.Commit.Branch)
	if len(view.Commit.Files) > 0 {
		fmt.Fprintf(w, "Files: %s\n", strings.Join(view.Commit.Files, ", "))
	}
	for _, session := range view.Sessions {
		fmt.Fprintf(w, "\nSession: %s\nSource: %s\n", session.SessionID, session.Source)
		if len(session.Models) > 0 {
			fmt.Fprintf(w, "Models: %s\n", strings.Join(session.Models, ", "))
		}
		if len(session.Messages) > 0 {
			fmt.Fprintf(w, "Messages: %d-%d\n", session.MessageFrom, session.MessageThrough)
			renderMessages(w, session.Messages)
		} else {
			fmt.Fprintf(w, "Events: %d-%d\n", session.EventFrom, session.EventThrough)
			renderEvents(w, session.Events)
		}
	}
	return nil
}

func showSessionConversation(sessionID string, asJSON bool, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	session, err := findSessionRecord(root, sessionID)
	if err != nil {
		return err
	}
	if asJSON {
		return writeJSONOutput(w, session)
	}
	fmt.Fprintf(w, "Session: %s\nSource: %s\nRepository: %s\nBranch: %s\nStarted: %s\nUpdated: %s\n", session.ID, session.Source, session.Repository.Name, session.Branch, session.StartedAt, session.UpdatedAt)
	if len(session.Models) > 0 {
		fmt.Fprintf(w, "Models: %s\n", strings.Join(session.Models, ", "))
	}
	fmt.Fprintf(w, "Messages: %d\nEvents: %d", session.MessageCount, session.EventCount)
	if len(session.EventKinds) > 0 {
		var kinds []string
		for _, event := range session.EventKinds {
			kinds = append(kinds, fmt.Sprintf("%s:%d", event.Name, event.Count))
		}
		fmt.Fprintf(w, " (%s)", strings.Join(kinds, ", "))
	}
	fmt.Fprintln(w)
	fmt.Fprintf(w, "Transcript: %s", session.TranscriptStatus)
	if session.TranscriptUnavailableReason != "" {
		fmt.Fprintf(w, " (%s)", session.TranscriptUnavailableReason)
	}
	fmt.Fprintln(w)
	if len(session.Commits) > 0 {
		fmt.Fprintln(w, "Commits:")
		for _, link := range session.Commits {
			fmt.Fprintf(w, "- %s %s", link.Commit.SHA, link.Commit.Subject)
			if link.MessageFrom > 0 {
				fmt.Fprintf(w, " (messages %d-%d)", link.MessageFrom, link.MessageThrough)
			} else {
				fmt.Fprintf(w, " (events %d-%d)", link.EventFrom, link.EventThrough)
			}
			fmt.Fprintln(w)
		}
	}
	fmt.Fprintln(w, "\nConversation:")
	if len(session.Messages) > 0 {
		renderMessages(w, session.Messages)
	} else {
		renderEvents(w, session.Events)
	}
	return nil
}

func listSessions(asJSON bool, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	records, err := listSessionRecords(root)
	if err != nil {
		return err
	}
	summaries := make([]sessionSummary, 0, len(records))
	for _, record := range records {
		summaries = append(summaries, sessionSummary{
			SchemaVersion: record.SchemaVersion, SessionID: record.ID, Source: record.Source, Repository: record.Repository,
			Branch: record.Branch, StartedAt: record.StartedAt, UpdatedAt: record.UpdatedAt,
			Models: record.Models, TranscriptStatus: record.TranscriptStatus,
			MessageCount: record.MessageCount, EventCount: record.EventCount,
			CommitCount: len(record.Commits),
		})
	}
	if asJSON {
		return writeJSONOutput(w, summaries)
	}
	if len(summaries) == 0 {
		fmt.Fprintln(w, "no sessions")
		return nil
	}
	for _, summary := range summaries {
		fmt.Fprintf(w, "%s  source=%s  updated=%s  commits=%d  messages=%d\n", summary.SessionID, summary.Source, summary.UpdatedAt, summary.CommitCount, summary.MessageCount)
	}
	return nil
}

func writeJSONOutput(w io.Writer, value any) error {
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	return encoder.Encode(value)
}

func renderMessages(w io.Writer, messages []conversationMessage) {
	for _, message := range messages {
		fmt.Fprintf(w, "\n%s:\n%s\n", strings.ToUpper(message.Role), message.Text)
	}
}

func renderEvents(w io.Writer, events []eventRecord) {
	for _, event := range events {
		fmt.Fprintf(w, "\nEVENT %s:\n%s\n", event.Event, strings.TrimSpace(string(event.Payload)))
	}
}

func readTraceState(root string) (traceState, error) {
	state := traceState{Sessions: map[string]sessionCursor{}}
	path, err := traceDataPath(root, "state.json")
	if err != nil {
		return traceState{}, err
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return state, nil
	}
	if err != nil {
		return traceState{}, fmt.Errorf("read trace state: %w", err)
	}
	if err := json.Unmarshal(data, &state); err != nil {
		return traceState{}, fmt.Errorf("parse trace state: %w", err)
	}
	if state.Sessions == nil {
		state.Sessions = map[string]sessionCursor{}
	}
	return state, nil
}

func writeTraceState(root string, state traceState) error {
	path, err := traceDataPath(root, "state.json")
	if err != nil {
		return err
	}
	return writeJSON(path, state)
}

func sessionStateKey(source string, sessionID string) string {
	return source + "/" + sessionID
}

var secretLine = regexp.MustCompile(`(?i)(api[_-]?key|token|password|secret|authorization)(["'\s:=]+)([^"',\s}]+)`)
var secretKey = regexp.MustCompile(`(?i)^(api[_-]?key|access[_-]?token|token|password|secret|authorization)$`)

func redactText(value string) string {
	return secretLine.ReplaceAllString(value, "$1$2[REDACTED]")
}

func redactEventRecords(events []eventRecord) []eventRecord {
	redacted := make([]eventRecord, len(events))
	copy(redacted, events)
	for i := range redacted {
		redacted[i].Payload = redactPayload(redacted[i].Payload)
	}
	return redacted
}

func redactPayload(payload json.RawMessage) json.RawMessage {
	var value any
	if err := json.Unmarshal(payload, &value); err != nil {
		return json.RawMessage(redactText(string(payload)))
	}
	data, err := json.Marshal(redactJSONValue(value))
	if err != nil {
		return json.RawMessage(`{}`)
	}
	return data
}

func redactJSONValue(value any) any {
	switch typed := value.(type) {
	case string:
		return redactText(typed)
	case []any:
		for i := range typed {
			typed[i] = redactJSONValue(typed[i])
		}
	case map[string]any:
		for key, child := range typed {
			if secretKey.MatchString(key) {
				typed[key] = "[REDACTED]"
				continue
			}
			typed[key] = redactJSONValue(child)
		}
	}
	return value
}
