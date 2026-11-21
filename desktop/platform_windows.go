//go:build windows

package main

import (
	_ "embed"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"golang.org/x/sys/windows"
)

//go:embed third_party/wintun/wintun.dll
var wintunDLL []byte

// Xray ищет wintun.dll рядом с exe: если её там нет — кладём вшитую (помощник уже администратор).
func prepareTunDriver() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	p := filepath.Join(filepath.Dir(exe), "wintun.dll")
	if st, err := os.Stat(p); err == nil && st.Size() == int64(len(wintunDLL)) {
		return nil
	}
	return os.WriteFile(p, wintunDLL, 0o644)
}

// Запуск помощника с повышением прав: окно UAC «Разрешить этому приложению…».
func launchElevated(exe string, args []string) error {
	quoted := make([]string, len(args))
	for i, a := range args {
		quoted[i] = syscall.EscapeArg(a)
	}
	verb, _ := windows.UTF16PtrFromString("runas")
	file, _ := windows.UTF16PtrFromString(exe)
	params, _ := windows.UTF16PtrFromString(strings.Join(quoted, " "))
	dir, _ := windows.UTF16PtrFromString(filepath.Dir(exe))
	err := windows.ShellExecute(0, verb, file, params, dir, windows.SW_HIDE)
	if err != nil {
		if errors.Is(err, windows.ERROR_CANCELLED) {
			return errors.New("отменено: без прав администратора режим TUN не включить")
		}
		return err
	}
	return nil
}

func processAlive(pid int) bool {
	h, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION|windows.SYNCHRONIZE, false, uint32(pid))
	if err != nil {
		return false
	}
	defer windows.CloseHandle(h)
	ev, err := windows.WaitForSingleObject(h, 0)
	return err == nil && ev == uint32(windows.WAIT_TIMEOUT)
}

// На Windows DNS туннеля ставит само ядро (поле dns + WFP).
func afterTunUp() error { return nil }
func afterTunDown()     {}
