package main

import (
	"fmt"
	"os"
)

func main() {
	a := app{stdin: os.Stdin, stdout: os.Stdout, stderr: os.Stderr}
	if err := a.run(os.Args[1:]); err != nil {
		fmt.Fprintln(a.stderr, err)
		os.Exit(1)
	}
}
