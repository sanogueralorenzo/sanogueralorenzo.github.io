package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

func gitRoot(dir string) (string, error) {
	out, err := command(dir, "git", "rev-parse", "--show-toplevel")
	if err != nil {
		return "", fmt.Errorf("not a git repository: %w", err)
	}
	return strings.TrimSpace(out), nil
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

func changedFiles(root string, commit string) ([]string, error) {
	out, err := command(root, "git", "diff-tree", "--no-commit-id", "--name-only", "-r", commit)
	if err != nil {
		return nil, fmt.Errorf("read changed files: %w", err)
	}
	var files []string
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			files = append(files, line)
		}
	}
	sort.Strings(files)
	return files, nil
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
	if _, err := command(root, "git", "update-ref", ref, commit); err != nil {
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
