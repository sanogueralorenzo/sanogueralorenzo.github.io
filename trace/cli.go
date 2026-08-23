package main

import (
	"errors"
	"fmt"
	"io"
	"strings"
)

type app struct {
	stdin  io.Reader
	stdout io.Writer
	stderr io.Writer
}

func (a app) run(args []string) error {
	if len(args) == 0 {
		return usage(a.stdout)
	}
	switch args[0] {
	case "help", "--help", "-h":
		return usage(a.stdout)
	case "init":
		root, err := gitRoot(".")
		if err != nil {
			return err
		}
		if err := initTrace(root); err != nil {
			return err
		}
		fmt.Fprintln(a.stdout, "trace initialized")
		return nil
	case "enable":
		root, err := gitRoot(".")
		if err != nil {
			return err
		}
		if err := enableTrace(root, a.stdout); err != nil {
			return err
		}
		return nil
	case "hooks":
		return a.runHook(args[1:])
	case "ingest":
		if len(args) != 3 {
			return errors.New("usage: trace ingest <source> <event>")
		}
		return a.capture(args[1], args[2])
	case "sessions":
		_, asJSON, err := outputArgs(args[1:], 0)
		if err != nil {
			return err
		}
		return listSessions(asJSON, a.stdout)
	case "show":
		values, asJSON, err := outputArgs(args[1:], 1)
		if err != nil {
			return errors.New("usage: trace show <commit> [--json]")
		}
		return showCommitConversation(values[0], asJSON, a.stdout)
	case "session":
		values, asJSON, err := outputArgs(args[1:], 1)
		if err != nil {
			return errors.New("usage: trace session <session-id> [--json]")
		}
		return showSessionConversation(values[0], asJSON, a.stdout)
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func usage(w io.Writer) error {
	_, err := fmt.Fprintln(w, `usage: trace <command>

commands:
  enable                         install local session capture
  sessions [--json]              list stored sessions
  show <commit> [--json]         show sessions linked to a commit
  session <session-id> [--json]  show one complete session
  ingest <source> <event>        ingest a JSON event from stdin
  init                           initialize storage only`)
	return err
}

func outputArgs(args []string, expected int) ([]string, bool, error) {
	var values []string
	asJSON := false
	for _, arg := range args {
		if arg == "--json" {
			asJSON = true
			continue
		}
		if strings.HasPrefix(arg, "-") {
			return nil, false, fmt.Errorf("unknown option %q", arg)
		}
		values = append(values, arg)
	}
	if len(values) != expected {
		return nil, false, errors.New("invalid arguments")
	}
	return values, asJSON, nil
}

func (a app) runHook(args []string) error {
	if len(args) != 2 {
		return errors.New("usage: trace hooks <source> <event>")
	}
	if args[0] == "git" {
		if args[1] != "post-commit" {
			return nil
		}
		root, err := gitRoot(".")
		if err != nil {
			return err
		}
		_, err = linkCommitSessions(root)
		return err
	}
	return a.capture(args[0], args[1])
}

func (a app) capture(source string, event string) error {
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	payload, err := io.ReadAll(a.stdin)
	if err != nil {
		return fmt.Errorf("read hook payload: %w", err)
	}
	return captureSessionEvent(root, source, event, payload)
}
