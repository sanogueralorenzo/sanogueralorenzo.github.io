package main

import (
	"errors"
	"fmt"
	"io"
	"sort"
	"strings"
)

func writeMemory(root string, record checkpointRecord) error {
	note := memoryNote(record)
	return writeRefFile(root, memoryRef, record.Commit+".md", []byte(note), "trace memory "+shortSHA(record.Commit))
}

func memoryNote(record checkpointRecord) string {
	var b strings.Builder
	fmt.Fprintf(&b, "# %s\n\n", shortSHA(record.Commit))
	fmt.Fprintf(&b, "Commit: `%s`\n\n", record.Commit)
	fmt.Fprintf(&b, "Checkpoint: `%s`\n\n", record.Checkpoint)
	subject := firstLine(record.Message)
	if subject == "" {
		subject = "(no commit message)"
	}
	fmt.Fprintf(&b, "Summary: %s\n\n", subject)
	if len(record.Sessions) == 0 {
		fmt.Fprintln(&b, "Source: commit message and diff fallback; no agent session was captured.")
	} else {
		var agents []string
		for _, session := range record.Sessions {
			agents = append(agents, session.Agent)
		}
		fmt.Fprintf(&b, "Source: captured agent sessions (%s).\n", strings.Join(unique(agents), ", "))
	}
	if len(record.Changed) > 0 {
		fmt.Fprintln(&b, "\nChanged files:")
		for _, file := range record.Changed {
			fmt.Fprintf(&b, "- `%s`\n", file)
		}
	}
	return b.String()
}

func shortSHA(sha string) string {
	if len(sha) < 12 {
		return sha
	}
	return sha[:12]
}

func firstLine(value string) string {
	for _, line := range strings.Split(value, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			return line
		}
	}
	return ""
}

func unique(values []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, value := range values {
		if !seen[value] {
			seen[value] = true
			out = append(out, value)
		}
	}
	sort.Strings(out)
	return out
}

func showMemory(commit string, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	sha, err := command(root, "git", "rev-parse", commit)
	if err != nil {
		return fmt.Errorf("resolve commit %q: %w", commit, err)
	}
	sha = strings.TrimSpace(sha)
	data, err := command(root, "git", "show", memoryRef+":"+sha+".md")
	if err != nil {
		return fmt.Errorf("memory not found for %s", commit)
	}
	_, err = io.WriteString(w, data)
	return err
}

func recallMemory(query string, w io.Writer) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	query = strings.ToLower(strings.TrimSpace(query))
	if query == "" {
		return errors.New("recall query cannot be empty")
	}
	out, err := command(root, "git", "ls-tree", "-r", "--name-only", memoryRef)
	if err != nil {
		fmt.Fprintln(w, "no matching memory")
		return nil
	}
	var matches []string
	for _, path := range strings.Split(out, "\n") {
		path = strings.TrimSpace(path)
		if path == "" || !strings.HasSuffix(path, ".md") {
			continue
		}
		data, err := command(root, "git", "show", memoryRef+":"+path)
		if err != nil {
			return fmt.Errorf("read memory %s: %w", path, err)
		}
		content := strings.ToLower(data)
		if strings.Contains(content, query) {
			matches = append(matches, memoryRef+":"+path+": "+firstLine(data))
		}
	}
	sort.Strings(matches)
	if len(matches) == 0 {
		fmt.Fprintln(w, "no matching memory")
		return nil
	}
	for _, match := range matches {
		fmt.Fprintln(w, match)
	}
	return nil
}
