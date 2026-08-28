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
	dataDir, err := traceDataPath(root)
	if err != nil {
		return err
	}
	dirs := []string{
		dataDir,
		filepath.Join(dataDir, "sessions"),
		filepath.Join(dataDir, "tmp"),
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0o750); err != nil {
			return fmt.Errorf("create %s: %w", dir, err)
		}
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
	if err := installPiExtension(root); err != nil {
		return err
	}
	if err := installOMPExtension(root); err != nil {
		return err
	}
	fmt.Fprintln(w, "trace enabled")
	for _, runtime := range []string{"codex", "claude", "opencode", "pi", "omp"} {
		if _, err := exec.LookPath(runtime); err != nil {
			fmt.Fprintf(w, "%s not found in PATH; Trace will not capture %s sessions until it is installed\n", runtime, runtime)
		}
	}
	return nil
}

func installGitHook(root string) error {
	gitDir, err := gitCommonDir(root)
	if err != nil {
		return err
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
