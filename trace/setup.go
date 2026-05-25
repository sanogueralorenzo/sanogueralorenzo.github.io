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
		filepath.Join(root, traceDir, "archive"),
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o750); err != nil {
			return fmt.Errorf("create %s: %w", dir, err)
		}
	}
	configPath := filepath.Join(root, traceDir, "config.json")
	if _, err := os.Stat(configPath); errors.Is(err, os.ErrNotExist) {
		cfg := []byte("{\n  \"version\": 1,\n  \"checkpoint_ref\": \"" + checkpointRef + "\",\n  \"memory_ref\": \"" + memoryRef + "\"\n}\n")
		if err := os.WriteFile(configPath, cfg, 0o600); err != nil {
			return fmt.Errorf("write %s: %w", configPath, err)
		}
	}
	ignore := "sessions/\ntmp/\narchive/\n"
	if err := os.WriteFile(filepath.Join(root, traceDir, ".gitignore"), []byte(ignore), 0o600); err != nil {
		return fmt.Errorf("write .trace/.gitignore: %w", err)
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
			fmt.Fprintf(w, "%s not found in PATH; rich %s capture requires the user-installed runtime, commit/diff fallback remains active\n", runtime, runtime)
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
	body := "#!/bin/sh\ntrace hooks git post-commit >/dev/null 2>&1 || true\n"
	if err := os.WriteFile(filepath.Join(hooksDir, "post-commit"), []byte(body), 0o755); err != nil {
		return fmt.Errorf("write post-commit hook: %w", err)
	}
	return nil
}
