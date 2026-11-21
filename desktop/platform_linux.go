//go:build linux

package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
)

func prepareTunDriver() error { return nil }

// Помощник через pkexec (окно пароля polkit). Без polkit — подсказка про sudo.
func launchElevated(exe string, args []string) error {
	pk, err := exec.LookPath("pkexec")
	if err != nil {
		return errors.New("нет pkexec (polkit): для режима TUN запустите в терминале  sudo " + exe + " " + strings.Join(args, " "))
	}
	cmd := exec.Command(pk, append([]string{exe}, args...)...)
	cmd.Stdout, cmd.Stderr = nil, nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return err
	}
	go func() {
		if err := cmd.Wait(); err != nil {
			if ee, ok := err.(*exec.ExitError); ok && (ee.ExitCode() == 126 || ee.ExitCode() == 127) {
				tlog.Log("pkexec: доступ не дан (%d)", ee.ExitCode())
			}
		}
	}()
	return nil
}

func processAlive(pid int) bool {
	return syscall.Kill(pid, 0) == nil || errors.Is(syscall.Kill(pid, 0), syscall.EPERM)
}

// DNS через туннель: systemd-resolved — DNS интерфейса bypen0 и маршрут «~.» для всех доменов.
// 1.1.1.1 уходит в туннель (маршруты 0/1 + 128/1), значит и запросы идут через узел.
// Без resolved DNS остаётся системным (пишем в журнал помощника).
var resolvedApplied bool

func afterTunUp() error {
	if _, err := exec.LookPath("resolvectl"); err != nil {
		return errors.New("нет resolvectl — DNS остаётся системным")
	}
	if out, err := exec.Command("systemctl", "is-active", "systemd-resolved").Output(); err != nil || strings.TrimSpace(string(out)) != "active" {
		return errors.New("systemd-resolved не запущен — DNS остаётся системным")
	}
	ifc := tunName()
	steps := [][]string{
		append([]string{"dns", ifc}, tunDNS...),
		{"domain", ifc, "~."},
		{"default-route", ifc, "true"},
	}
	for _, s := range steps {
		if out, err := exec.Command("resolvectl", s...).CombinedOutput(); err != nil {
			return fmt.Errorf("resolvectl %s: %v %s", strings.Join(s, " "), err, strings.TrimSpace(string(out)))
		}
	}
	_ = exec.Command("resolvectl", "flush-caches").Run()
	resolvedApplied = true
	return nil
}

func afterTunDown() {
	if resolvedApplied {
		_ = exec.Command("resolvectl", "revert", tunName()).Run()
		_ = exec.Command("resolvectl", "flush-caches").Run()
		resolvedApplied = false
	}
	_ = os.Remove("/run/bypen.none")
}
