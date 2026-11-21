// Где лежат файлы приложения: настройки, профиль узлов, журнал, события.
// Windows: %AppData%\Bypen, Linux: ~/.config/bypen.
package main

import (
	"os"
	"path/filepath"
	"runtime"
)

func appDir() string {
	base, err := os.UserConfigDir()
	if err != nil {
		base = os.TempDir()
	}
	name := "bypen"
	if runtime.GOOS == "windows" {
		name = "Bypen"
	}
	d := filepath.Join(base, name)
	_ = os.MkdirAll(d, 0o700)
	return d
}

func pathIn(name string) string { return filepath.Join(appDir(), name) }

var (
	statePath    = func() string { return pathIn("state.json") }    // вход: токены, имя, device_id
	settingsPath = func() string { return pathIn("settings.json") } // настройки
	profilePath  = func() string { return pathIn("profile.json") }  // подписанный список узлов (payload как есть)
	logPath      = func() string { return pathIn("tunnel.log") }
	xrayLogPath  = func() string { return pathIn("xray.log") }
	eventsPath   = func() string { return pathIn("events.jsonl") }
)

// platformTag — как клиент называет себя серверу.
func platformTag() string {
	switch runtime.GOOS {
	case "windows":
		return "windows"
	case "linux":
		return "linux"
	}
	return runtime.GOOS
}

func deviceName() string {
	switch runtime.GOOS {
	case "windows":
		return "Бупень · Windows"
	case "linux":
		return "Бупень · Linux"
	}
	return "Бупень · " + runtime.GOOS
}
