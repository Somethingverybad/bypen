//go:build !windows && !linux

package main

import (
	"errors"
	"syscall"
)

// Для проверки на маке: TUN здесь не поддерживается (на маке — отдельное приложение).
func prepareTunDriver() error                    { return nil }
func launchElevated(exe string, args []string) error { return errors.New("TUN только на Windows и Linux") }
func processAlive(pid int) bool                  { return syscall.Kill(pid, 0) == nil }
func afterTunUp() error                          { return nil }
func afterTunDown()                              {}
