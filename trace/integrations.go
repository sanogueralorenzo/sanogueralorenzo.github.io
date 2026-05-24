package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

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
