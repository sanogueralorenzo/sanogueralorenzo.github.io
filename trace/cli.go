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
	case "show":
		if len(args) != 2 {
			return errors.New("usage: trace show <commit>")
		}
		return showMemory(args[1], a.stdout)
	case "recall":
		if len(args) < 2 {
			return errors.New("usage: trace recall <query>")
		}
		return recallMemory(strings.Join(args[1:], " "), a.stdout)
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func usage(w io.Writer) error {
	_, err := fmt.Fprintln(w, "usage: trace <init|enable|hooks|show|recall>")
	return err
}

func (a app) runHook(args []string) error {
	if len(args) < 2 {
		return errors.New("usage: trace hooks <git|codex|claude-code|opencode> <event>")
	}
	if args[0] == "git" {
		if args[1] != "post-commit" {
			return nil
		}
		root, err := gitRoot(".")
		if err != nil {
			return err
		}
		_, err = commitTrace(root)
		return err
	}
	root, err := gitRoot(".")
	if err != nil {
		return err
	}
	payload, err := io.ReadAll(a.stdin)
	if err != nil {
		return fmt.Errorf("read hook payload: %w", err)
	}
	return captureAgentHook(root, args[0], args[1], payload)
}
