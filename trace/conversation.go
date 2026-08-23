package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

type conversationMessage struct {
	Role string `json:"role"`
	Text string `json:"text"`
}

type sessionRecord struct {
	ID        string                `json:"session_id"`
	Agent     string                `json:"agent"`
	UpdatedAt string                `json:"updated_at"`
	Messages  []conversationMessage `json:"messages,omitempty"`
	Events    []eventRecord         `json:"events"`
}

type sessionLink struct {
	SessionID      string `json:"session_id"`
	Agent          string `json:"agent"`
	MessageFrom    int    `json:"message_from,omitempty"`
	MessageThrough int    `json:"message_through,omitempty"`
	EventFrom      int    `json:"event_from"`
	EventThrough   int    `json:"event_through"`
}

type commitConversation struct {
	Commit    string        `json:"commit"`
	CreatedAt string        `json:"created_at"`
	Sessions  []sessionLink `json:"sessions"`
}

type sessionCursor struct {
	Messages int `json:"messages"`
	Events   int `json:"events"`
}

type traceState struct {
	Sessions map[string]sessionCursor `json:"sessions"`
}

func linkCommitConversations(root string) (*commitConversation, error) {
	if err := initTrace(root); err != nil {
		return nil, err
	}
	commit, err := command(root, "git", "rev-parse", "HEAD")
	if err != nil {
		return nil, fmt.Errorf("resolve HEAD: %w", err)
	}
	commit = strings.TrimSpace(commit)
	records, err := collectSessionRecords(root)
	if err != nil {
		return nil, err
	}
	state, err := readTraceState(root)
	if err != nil {
		return nil, err
	}
	result := &commitConversation{
		Commit:    commit,
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
	for _, record := range records {
		key := sessionStateKey(record.Agent, record.ID)
		previous := state.Sessions[key]
		if len(record.Messages) <= previous.Messages && len(record.Events) <= previous.Events {
			continue
		}
		if err := writeSessionRecord(root, record); err != nil {
			return nil, err
		}
		link := sessionLink{
			SessionID:    record.ID,
			Agent:        record.Agent,
			EventFrom:    previous.Events + 1,
			EventThrough: len(record.Events),
		}
		if len(record.Messages) > previous.Messages {
			link.MessageFrom = previous.Messages + 1
			link.MessageThrough = len(record.Messages)
		}
		result.Sessions = append(result.Sessions, link)
		state.Sessions[key] = sessionCursor{
			Messages: len(record.Messages),
			Events:   len(record.Events),
		}
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

func collectSessionRecords(root string) ([]sessionRecord, error) {
	base := filepath.Join(root, traceDir, "sessions")
	var records []sessionRecord
	err := filepath.WalkDir(base, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.IsDir() || !strings.HasSuffix(path, ".jsonl") {
			return nil
		}
		lines, err := readSessionLines(path)
		if err != nil {
			return err
		}
		if len(lines) == 0 {
			return nil
		}
		record := sessionRecord{
			ID:        lines[0].SessionID,
			Agent:     lines[0].Agent,
			UpdatedAt: lines[len(lines)-1].Timestamp,
			Events:    lines,
			Messages:  sessionTranscriptMessages(lines),
		}
		records = append(records, record)
		return nil
	})
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("collect sessions: %w", err)
	}
	sort.Slice(records, func(i, j int) bool {
		if records[i].Agent == records[j].Agent {
			return records[i].ID < records[j].ID
		}
		return records[i].Agent < records[j].Agent
	})
	return records, nil
}

func sessionTranscriptMessages(events []eventRecord) []conversationMessage {
	for i := len(events) - 1; i >= 0; i-- {
		path := events[i].TranscriptPath
		if path == "" {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		messages := parseTranscriptMessages(data)
		if len(messages) > 0 {
			return messages
		}
	}
	return messagesFromEvents(events)
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
		if len(unique) > 0 {
			previous := unique[len(unique)-1]
			if previous.Role == message.Role && previous.Text == message.Text {
				continue
			}
		}
		unique = append(unique, message)
	}
	return unique
}

func writeSessionRecord(root string, record sessionRecord) error {
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal session %s: %w", record.ID, err)
	}
	data = append(data, '\n')
	path := filepath.ToSlash(filepath.Join(safeName(record.Agent), safeName(record.ID)+".json"))
	return writeRefFile(root, sessionRef, path, data, "trace session "+record.ID)
}

func writeCommitConversation(root string, record commitConversation) error {
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal commit conversation: %w", err)
	}
	data = append(data, '\n')
	if _, err := commandEnv(root, nil, data, "git", "notes", "--ref="+noteRef, "add", "-f", "-F", "-", record.Commit); err != nil {
		return fmt.Errorf("link conversation to commit %s: %w", record.Commit, err)
	}
	return nil
}

func readCommitConversation(root string, commit string) (commitConversation, error) {
	sha, err := command(root, "git", "rev-parse", commit)
	if err != nil {
		return commitConversation{}, fmt.Errorf("resolve commit %q: %w", commit, err)
	}
	sha = strings.TrimSpace(sha)
	data, err := command(root, "git", "notes", "--ref="+noteRef, "show", sha)
	if err != nil {
		return commitConversation{}, fmt.Errorf("no conversation linked to %s", commit)
	}
	var record commitConversation
	if err := json.Unmarshal([]byte(data), &record); err != nil {
		return commitConversation{}, fmt.Errorf("parse conversation for %s: %w", commit, err)
	}
	return record, nil
}

func findSessionRecord(root string, sessionID string) (sessionRecord, error) {
	out, err := command(root, "git", "ls-tree", "-r", "--name-only", sessionRef)
	if err != nil {
		return sessionRecord{}, fmt.Errorf("session %q not found", sessionID)
	}
	for _, path := range strings.Split(out, "\n") {
		path = strings.TrimSpace(path)
		if path == "" || !strings.HasSuffix(path, ".json") {
			continue
		}
		data, err := command(root, "git", "show", sessionRef+":"+path)
		if err != nil {
			return sessionRecord{}, fmt.Errorf("read session %s: %w", sessionID, err)
		}
		var record sessionRecord
		if json.Unmarshal([]byte(data), &record) == nil && record.ID == sessionID {
			return record, nil
		}
	}
	return sessionRecord{}, fmt.Errorf("session %q not found", sessionID)
}

func showCommitConversation(commit string, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	record, err := readCommitConversation(root, commit)
	if err != nil {
		return err
	}
	fmt.Fprintf(w, "Commit: %s\n", record.Commit)
	for _, link := range record.Sessions {
		session, err := findSessionRecord(root, link.SessionID)
		if err != nil {
			return err
		}
		fmt.Fprintf(w, "\nSession: %s (%s)\n", session.ID, session.Agent)
		renderSessionRange(w, session, link)
	}
	return nil
}

func showSessionConversation(sessionID string, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	session, err := findSessionRecord(root, sessionID)
	if err != nil {
		return err
	}
	fmt.Fprintf(w, "Session: %s\nAgent: %s\n", session.ID, session.Agent)
	links, err := commitLinksForSession(root, sessionID)
	if err != nil {
		return err
	}
	if len(links) > 0 {
		fmt.Fprintln(w, "Commits:")
		for _, item := range links {
			fmt.Fprintf(w, "- %s", item.Commit)
			if item.MessageFrom > 0 {
				fmt.Fprintf(w, " (messages %d-%d)", item.MessageFrom, item.MessageThrough)
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

func renderSessionRange(w io.Writer, session sessionRecord, link sessionLink) {
	if link.MessageFrom > 0 && link.MessageThrough >= link.MessageFrom && link.MessageThrough <= len(session.Messages) {
		fmt.Fprintf(w, "Messages: %d-%d\n", link.MessageFrom, link.MessageThrough)
		renderMessages(w, session.Messages[link.MessageFrom-1:link.MessageThrough])
		return
	}
	if link.EventFrom > 0 && link.EventThrough >= link.EventFrom && link.EventThrough <= len(session.Events) {
		fmt.Fprintf(w, "Events: %d-%d\n", link.EventFrom, link.EventThrough)
		renderEvents(w, session.Events[link.EventFrom-1:link.EventThrough])
	}
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

func commitLinksForSession(root string, sessionID string) ([]sessionLinkWithCommit, error) {
	out, err := command(root, "git", "notes", "--ref="+noteRef, "list")
	if err != nil {
		return nil, nil
	}
	var links []sessionLinkWithCommit
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		record, err := readCommitConversation(root, fields[1])
		if err != nil {
			return nil, err
		}
		for _, link := range record.Sessions {
			if link.SessionID == sessionID {
				links = append(links, sessionLinkWithCommit{Commit: record.Commit, CreatedAt: record.CreatedAt, sessionLink: link})
			}
		}
	}
	sort.Slice(links, func(i, j int) bool { return links[i].CreatedAt < links[j].CreatedAt })
	return links, nil
}

type sessionLinkWithCommit struct {
	Commit    string
	CreatedAt string
	sessionLink
}

func readTraceState(root string) (traceState, error) {
	state := traceState{Sessions: map[string]sessionCursor{}}
	data, err := os.ReadFile(filepath.Join(root, traceDir, "state.json"))
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
	return writeJSON(filepath.Join(root, traceDir, "state.json"), state)
}

func sessionStateKey(agent string, sessionID string) string {
	return agent + "/" + sessionID
}

var secretLine = regexp.MustCompile(`(?i)(api[_-]?key|token|password|secret|authorization)(["'\s:=]+)([^"',\s}]+)`)

func redactText(value string) string {
	return secretLine.ReplaceAllString(value, "$1$2[REDACTED]")
}
