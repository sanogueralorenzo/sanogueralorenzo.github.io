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
		event   string
		name    string
		timeout int
	}{
		{"SessionStart", "session-start", 30},
		{"SessionEnd", "session-end", 3},
		{"UserPromptSubmit", "turn-start", 30},
		{"Stop", "turn-end", 30},
		{"PostToolUse", "", 0},
	} {
		hooks[item.event] = replaceCaptureHook(hooks[item.event], nil, "codex", item.name, item.timeout)
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
	Hooks map[string][]hookMatcher `json:"hooks,omitempty"`
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
	for _, item := range []struct {
		event   string
		matcher *string
		name    string
	}{
		{"SessionStart", strPtr(""), "session-start"},
		{"SessionEnd", strPtr(""), "session-end"},
		{"UserPromptSubmit", strPtr(""), "turn-start"},
		{"Stop", strPtr(""), "turn-end"},
		{"PreToolUse", nil, ""},
		{"PostToolUse", nil, ""},
	} {
		hooks[item.event] = replaceCaptureHook(hooks[item.event], item.matcher, "claude-code", item.name, 0)
	}
	rawHooks, err := json.Marshal(hooks)
	if err != nil {
		return fmt.Errorf("marshal Claude hooks: %w", err)
	}
	top["hooks"] = rawHooks
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

func installPiExtension(root string) error {
	return installSessionExtension(root, ".pi", "@earendil-works/pi-coding-agent", "pi", "TRACE_PI_NESTED")
}

func installOMPExtension(root string) error {
	return installSessionExtension(root, ".omp", "@oh-my-pi/pi-coding-agent", "omp", "TRACE_OMP_NESTED")
}

func installSessionExtension(root string, configDir string, packageName string, source string, nestedMarker string) error {
	path := filepath.Join(root, configDir, "extensions", "trace", "index.ts")
	content := strings.NewReplacer(
		"__PACKAGE__", packageName,
		"__SOURCE__", source,
		"__NESTED_MARKER__", nestedMarker,
	).Replace(sessionExtension)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("create %s extension dir: %w", source, err)
	}
	return os.WriteFile(path, []byte(content), 0o644)
}

func replaceCaptureHook(groups []hookMatcher, matcher *string, source string, event string, timeout int) []hookMatcher {
	groups = removeTraceHooks(groups, "trace hooks "+source+" ")
	groups = removeTraceHooks(groups, "trace ingest "+source+" ")
	if event == "" {
		return groups
	}
	return addCommandHook(groups, matcher, "trace ingest "+source+" "+event, timeout)
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

const sessionExtension = `// Trace extension. Auto-generated by trace enable.
import type { ExtensionAPI } from "__PACKAGE__";
import { execFile } from "node:child_process";

export default function (agent: ExtensionAPI) {
  const nested = Boolean(process.env.__NESTED_MARKER__);
  process.env.__NESTED_MARKER__ = "1";
  if (nested) return;

  function ingest(event: string, data: Record<string, unknown>): Promise<void> {
    return new Promise((resolve) => {
      try {
        const child = execFile(
          "trace",
          ["ingest", "__SOURCE__", event],
          { cwd: data.cwd as string, timeout: 10000, windowsHide: true },
          () => resolve(),
        );
        child.stdin?.end(JSON.stringify(data));
      } catch {
        resolve();
      }
    });
  }

  type SessionContext = {
    cwd: string;
    model?: { provider?: string; id?: string } | null;
    sessionManager: { getSessionId(): string; getSessionFile(): string | undefined };
  };

  function sessionData(ctx: SessionContext, prompt?: string): Record<string, unknown> {
    const model = ctx.model ? [ctx.model.provider, ctx.model.id].filter(Boolean).join("/") : undefined;
    return {
      session_id: ctx.sessionManager.getSessionId(),
      transcript_path: ctx.sessionManager.getSessionFile(),
      cwd: ctx.cwd,
      ...(model ? { model } : {}),
      ...(prompt ? { prompt } : {}),
    };
  }

  agent.on("session_start", async (_event, ctx) => {
    await ingest("session-start", sessionData(ctx));
  });
  agent.on("before_agent_start", async (event, ctx) => {
    await ingest("turn-start", sessionData(ctx, event.prompt));
  });
  agent.on("agent_end", async (_event, ctx) => {
    await ingest("turn-end", sessionData(ctx));
  });
}
`

const openCodePlugin = `// Trace CLI plugin for OpenCode.
// Auto-generated by trace enable.
// Sends canonical lifecycle events through trace ingest.
import { spawn, spawnSync } from "node:child_process"
import type { Plugin } from "@opencode-ai/plugin"

export const TracePlugin: Plugin = async ({ directory }) => {
  const TRACE_CMD = "__TRACE_CMD__"
  const seenUserMessages = new Set<string>()
  let currentSessionID: string | null = null
  let currentModel: string | null = null
  const messageStore = new Map<string, any>()

  function ingestCmd(event: string): string[] {
    return [TRACE_CMD, "ingest", "opencode", event]
  }

  async function ingest(event: string, payload: Record<string, unknown>) {
    try {
      const [cmd, ...args] = ingestCmd(event)
      await new Promise<void>((resolve) => {
        const proc = spawn(cmd, args, {
          cwd: directory,
          stdio: ["pipe", "ignore", "ignore"],
        })
        proc.on("error", () => resolve())
        proc.on("close", () => resolve())
        proc.stdin?.end(JSON.stringify(payload) + "\n")
      })
    } catch {}
  }

  function ingestSync(event: string, payload: Record<string, unknown>) {
    try {
      const [cmd, ...args] = ingestCmd(event)
      spawnSync(cmd, args, {
        cwd: directory,
        input: JSON.stringify(payload) + "\n",
        stdio: ["pipe", "ignore", "ignore"],
      })
    } catch {}
  }

  function resetSession(sessionID: string): boolean {
    if (currentSessionID === sessionID) return false
    seenUserMessages.clear()
    messageStore.clear()
    currentModel = null
    currentSessionID = sessionID
    return true
  }

  return {
    event: async ({ event }) => {
      try {
        switch (event.type) {
          case "session.created": {
            const session = (event as any).properties?.info
            if (!session?.id) break
            if (resetSession(session.id)) {
              await ingest("session-start", { session_id: session.id })
            }
            break
          }
          case "message.updated": {
            const msg = (event as any).properties?.info
            if (!msg) break
            if (msg.sessionID && resetSession(msg.sessionID)) {
              ingestSync("session-start", { session_id: msg.sessionID })
            }
            messageStore.set(msg.id, msg)
            if (msg.role === "assistant" && msg.modelID) currentModel = msg.modelID
            if (msg.role === "user" && !seenUserMessages.has(msg.id)) {
              seenUserMessages.add(msg.id)
              const sessionID = msg.sessionID ?? currentSessionID
              if (sessionID) ingestSync("turn-start", { session_id: sessionID, prompt: "", model: currentModel ?? "" })
            }
            break
          }
          case "message.part.updated": {
            const part = (event as any).properties?.part
            const msg = part?.messageID ? messageStore.get(part.messageID) : null
            if (msg?.role === "user" && part.type === "text" && !seenUserMessages.has(msg.id)) {
              seenUserMessages.add(msg.id)
              const sessionID = msg.sessionID ?? currentSessionID
              if (sessionID) ingestSync("turn-start", { session_id: sessionID, prompt: part.text ?? "", model: currentModel ?? "" })
            }
            break
          }
          case "session.status": {
            const props = (event as any).properties
            if (props?.status?.type !== "idle") break
            const sessionID = props?.sessionID ?? currentSessionID
            if (sessionID) ingestSync("turn-end", { session_id: sessionID, model: currentModel ?? "" })
            break
          }
          case "session.deleted": {
            const sessionID = (event as any).properties?.info?.id
            if (!sessionID) break
            if (currentSessionID === sessionID) currentSessionID = null
            ingestSync("session-end", { session_id: sessionID })
            break
          }
          case "server.instance.disposed": {
            if (!currentSessionID) break
            const sessionID = currentSessionID
            currentSessionID = null
            ingestSync("session-end", { session_id: sessionID })
            break
          }
        }
      } catch {}
    },
  }
}
`
