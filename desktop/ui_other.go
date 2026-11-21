//go:build !windows && !linux

package main

import (
	"fmt"
	"os"
	"os/exec"
)

// Для проверки на маке: открыть интерфейс в браузере.
func runUI(url string, app *App) {
	openExternal(url)
	<-quitCh
}

func openExternal(url string) { _ = exec.Command("open", url).Start() }

func showError(msg string) { fmt.Fprintln(os.Stderr, msg) }
