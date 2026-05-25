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
		hooks[item.event] = removeTraceHooks(hooks[item.event], "trace hooks codex ")
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
		{"PreToolUse", strPtr("Task"), "pre-task"},
		{"PostToolUse", strPtr("Task"), "post-task"},
	} {
		hooks[item.event] = removeTraceHooks(hooks[item.event], "trace hooks claude-code ")
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

func removeTraceHooks(groups []hookMatcher, commandPrefix string) []hookMatcher {
	var kept []hookMatcher
	for _, group := range groups {
		var hooks []hookCommand
		for _, hook := range group.Hooks {
			if !strings.HasPrefix(hook.Command, commandPrefix) {
				hooks = append(hooks, hook)
			}
		}
		if len(hooks) > 0 {
			group.Hooks = hooks
			kept = append(kept, group)
		}
	}
	return kept
}

func strPtr(value string) *string {
	return &value
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
