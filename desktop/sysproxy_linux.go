//go:build linux

package main

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"strings"
)

// GNOME (gsettings) и KDE (kwriteconfig5/6). Многие программы в Linux системный прокси
// не читают — для них режим TUN.
type linuxProxyBackup struct {
	GnomeMode string `json:"gnomeMode,omitempty"`
	KdeType   string `json:"kdeType,omitempty"`
	Kwrite    string `json:"kwrite,omitempty"`
}

func proxyBackupPath() string { return pathIn("proxy-backup.json") }

func kwrite() string {
	for _, n := range []string{"kwriteconfig6", "kwriteconfig5"} {
		if p, err := exec.LookPath(n); err == nil {
			return p
		}
	}
	return ""
}

func sysProxyEnable() error {
	var b linuxProxyBackup
	applied := false
	if _, err := exec.LookPath("gsettings"); err == nil {
		if out, err := exec.Command("gsettings", "get", "org.gnome.system.proxy", "mode").Output(); err == nil {
			b.GnomeMode = strings.Trim(strings.TrimSpace(string(out)), "'")
			set := [][]string{
				{"org.gnome.system.proxy.http", "host", "127.0.0.1"}, {"org.gnome.system.proxy.http", "port", "10809"},
				{"org.gnome.system.proxy.https", "host", "127.0.0.1"}, {"org.gnome.system.proxy.https", "port", "10809"},
				{"org.gnome.system.proxy.socks", "host", "127.0.0.1"}, {"org.gnome.system.proxy.socks", "port", "10808"},
				{"org.gnome.system.proxy", "ignore-hosts", "['localhost', '127.0.0.0/8', '::1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']"},
				{"org.gnome.system.proxy", "mode", "manual"},
			}
			ok := true
			for _, s := range set {
				if exec.Command("gsettings", append([]string{"set"}, s...)...).Run() != nil {
					ok = false
				}
			}
			applied = applied || ok
		}
	}
	if kw := kwrite(); kw != "" {
		b.Kwrite = kw
		if out, err := exec.Command(strings.Replace(kw, "kwriteconfig", "kreadconfig", 1), "--file", "kioslaverc", "--group", "Proxy Settings", "--key", "ProxyType").Output(); err == nil {
			b.KdeType = strings.TrimSpace(string(out))
		}
		set := [][]string{{"ProxyType", "1"}, {"httpProxy", "http://127.0.0.1 10809"}, {"httpsProxy", "http://127.0.0.1 10809"}, {"socksProxy", "socks://127.0.0.1 10808"}, {"NoProxyFor", "localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"}}
		ok := true
		for _, s := range set {
			if exec.Command(kw, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", s[0], s[1]).Run() != nil {
				ok = false
			}
		}
		_ = exec.Command("dbus-send", "--type=signal", "/KIO/Scheduler", "org.kde.KIO.Scheduler.reparseSlaveConfiguration", "string:").Run()
		applied = applied || ok
	}
	if !applied {
		return errors.New("не нашёл, где включить системный прокси (нет gsettings/kwriteconfig) — выберите режим TUN")
	}
	if _, err := os.Stat(proxyBackupPath()); err != nil {
		bb, _ := json.Marshal(b)
		_ = os.WriteFile(proxyBackupPath(), bb, 0o600)
	}
	return nil
}

func sysProxyDisable() error {
	var b linuxProxyBackup
	if bb, err := os.ReadFile(proxyBackupPath()); err == nil {
		_ = json.Unmarshal(bb, &b)
	}
	if _, err := exec.LookPath("gsettings"); err == nil {
		mode := b.GnomeMode
		if mode == "" || mode == "manual" {
			mode = "none"
		}
		_ = exec.Command("gsettings", "set", "org.gnome.system.proxy", "mode", mode).Run()
	}
	if kw := kwrite(); kw != "" {
		t := b.KdeType
		if t == "" || t == "1" {
			t = "0"
		}
		_ = exec.Command(kw, "--file", "kioslaverc", "--group", "Proxy Settings", "--key", "ProxyType", t).Run()
		_ = exec.Command("dbus-send", "--type=signal", "/KIO/Scheduler", "org.kde.KIO.Scheduler.reparseSlaveConfiguration", "string:").Run()
	}
	_ = os.Remove(proxyBackupPath())
	return nil
}

func sysProxyLeftover() bool {
	_, err := os.Stat(proxyBackupPath())
	return err == nil
}
