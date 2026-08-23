package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func initTrace(root string) error {
	dirs := []string{
		filepath.Join(root, traceDir),
		filepath.Join(root, traceDir, "sessions"),
		filepath.Join(root, traceDir, "tmp"),
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o750); err != nil {
			return fmt.Errorf("create %s: %w", dir, err)
		}
	}
	return addLocalExclude(root, traceDir+"/")
}

func addLocalExclude(root string, pattern string) error {
	path, err := command(root, "git", "rev-parse", "--git-path", "info/exclude")
	if err != nil {
		return fmt.Errorf("resolve local Git exclude: %w", err)
	}
	path = strings.TrimSpace(path)
	if !filepath.IsAbs(path) {
		path = filepath.Join(root, path)
	}
	existing, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read local Git exclude: %w", err)
	}
	for _, line := range strings.Split(string(existing), "\n") {
		if strings.TrimSpace(line) == pattern {
			return nil
		}
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("create local Git info directory: %w", err)
	}
	content := string(existing)
	if content != "" && !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	content += pattern + "\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		return fmt.Errorf("write local Git exclude: %w", err)
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
			fmt.Fprintf(w, "%s not found in PATH; Trace will not capture %s sessions until it is installed\n", runtime, runtime)
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
	path := filepath.Join(hooksDir, "post-commit")
	existing, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read post-commit hook: %w", err)
	}
	body := mergeGitHook(string(existing))
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		return fmt.Errorf("write post-commit hook: %w", err)
	}
	return nil
}

func mergeGitHook(existing string) string {
	const (
		start  = "# trace:start"
		end    = "# trace:end"
		legacy = "#!/bin/sh\ntrace hooks git post-commit >/dev/null 2>&1 || true"
		block  = start + "\nif ! trace hooks git post-commit >/dev/null; then\n  echo \"trace: failed to link commit\" >&2\nfi\n" + end + "\n"
	)
	if strings.TrimSpace(existing) == legacy {
		existing = ""
	}
	if startAt := strings.Index(existing, start); startAt >= 0 {
		endAt := strings.Index(existing[startAt:], end)
		if endAt >= 0 {
			endAt = startAt + endAt + len(end)
			existing = existing[:startAt] + strings.TrimLeft(existing[endAt:], "\n")
		}
	}
	if strings.TrimSpace(existing) == "" {
		existing = "#!/bin/sh\n"
	}
	if !strings.HasSuffix(existing, "\n") {
		existing += "\n"
	}
	return existing + block
}
