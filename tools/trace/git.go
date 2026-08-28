package main

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func gitRoot(dir string) (string, error) {
	out, err := command(dir, "git", "rev-parse", "--show-toplevel")
	if err != nil {
		return "", fmt.Errorf("not a git repository: %w", err)
	}
	return strings.TrimSpace(out), nil
}

func gitCommonDir(root string) (string, error) {
	out, err := command(root, "git", "rev-parse", "--git-common-dir")
	if err != nil {
		return "", fmt.Errorf("resolve git common dir: %w", err)
	}
	path := strings.TrimSpace(out)
	if !filepath.IsAbs(path) {
		path = filepath.Join(root, path)
	}
	path = filepath.Clean(path)
	canonical, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", fmt.Errorf("resolve git common dir path: %w", err)
	}
	return canonical, nil
}

func traceDataPath(root string, elements ...string) (string, error) {
	commonDir, err := gitCommonDir(root)
	if err != nil {
		return "", err
	}
	gitDir, err := command(root, "git", "rev-parse", "--git-dir")
	if err != nil {
		return "", fmt.Errorf("resolve worktree git dir: %w", err)
	}
	gitDir = strings.TrimSpace(gitDir)
	if !filepath.IsAbs(gitDir) {
		gitDir = filepath.Join(root, gitDir)
	}
	gitDir, err = filepath.EvalSymlinks(filepath.Clean(gitDir))
	if err != nil {
		return "", fmt.Errorf("resolve worktree git dir path: %w", err)
	}
	worktreeKey := fmt.Sprintf("%x", sha256.Sum256([]byte(gitDir)))
	parts := append([]string{commonDir, traceDataDir, "worktrees", worktreeKey}, elements...)
	return filepath.Join(parts...), nil
}

func command(dir string, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			return "", fmt.Errorf("%s: %w", msg, err)
		}
		return "", err
	}
	return string(out), nil
}

func commandEnv(dir string, env []string, input []byte, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), env...)
	cmd.Stdin = bytes.NewReader(input)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			return "", fmt.Errorf("%s: %w", msg, err)
		}
		return "", err
	}
	return string(out), nil
}

func writeRefFile(root string, ref string, path string, data []byte, message string) error {
	index, err := os.CreateTemp("", "trace-index-*")
	if err != nil {
		return fmt.Errorf("create temp index: %w", err)
	}
	indexPath := index.Name()
	index.Close()
	defer os.Remove(indexPath)
	env := []string{"GIT_INDEX_FILE=" + indexPath}
	if _, err := commandEnv(root, env, nil, "git", "read-tree", "--empty"); err != nil {
		return fmt.Errorf("prepare trace index: %w", err)
	}
	parent, hasParent := currentRefCommit(root, ref)
	if hasParent {
		if _, err := commandEnv(root, env, nil, "git", "read-tree", ref); err != nil {
			return fmt.Errorf("read trace ref %s: %w", ref, err)
		}
	}
	blob, err := commandEnv(root, env, data, "git", "hash-object", "-w", "--stdin")
	if err != nil {
		return fmt.Errorf("write trace blob: %w", err)
	}
	blob = strings.TrimSpace(blob)
	if _, err := commandEnv(root, env, nil, "git", "update-index", "--add", "--cacheinfo", "100644,"+blob+","+path); err != nil {
		return fmt.Errorf("stage trace blob: %w", err)
	}
	tree, err := commandEnv(root, env, nil, "git", "write-tree")
	if err != nil {
		return fmt.Errorf("write trace tree: %w", err)
	}
	tree = strings.TrimSpace(tree)
	args := []string{"commit-tree", tree, "-m", message}
	if hasParent {
		args = append(args, "-p", parent)
	}
	commit, err := commandEnv(root, env, nil, "git", args...)
	if err != nil {
		return fmt.Errorf("commit trace tree: %w", err)
	}
	commit = strings.TrimSpace(commit)
	previous := strings.Repeat("0", len(commit))
	if hasParent {
		previous = parent
	}
	if _, err := command(root, "git", "update-ref", ref, commit, previous); err != nil {
		return fmt.Errorf("update trace ref %s: %w", ref, err)
	}
	return nil
}

func currentRefCommit(root string, ref string) (string, bool) {
	out, err := command(root, "git", "rev-parse", "--verify", ref+"^{commit}")
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(out), true
}

func pushTraceRefs(root string, remote string) error {
	_, err := command(root, "git", "push", "--", remote, sessionRefspec(), noteRef+":"+noteRef)
	if err != nil {
		return fmt.Errorf("push Trace refs to %s: %w", remote, err)
	}
	return nil
}

func fetchTraceRefs(root string, remote string) error {
	_, err := command(root, "git", "fetch", "--", remote, sessionRefspec(), noteRef+":"+noteRef)
	if err != nil {
		return fmt.Errorf("fetch Trace refs from %s: %w", remote, err)
	}
	return nil
}

func sessionRefspec() string {
	return sessionRefPrefix + "/*:" + sessionRefPrefix + "/*"
}
