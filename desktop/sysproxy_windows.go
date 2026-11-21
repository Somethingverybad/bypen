//go:build windows

package main

import (
	"encoding/json"
	"os"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const inetKey = `Software\Microsoft\Windows\CurrentVersion\Internet Settings`

type savedProxy struct {
	Enable   uint32 `json:"enable"`
	Server   string `json:"server"`
	Override string `json:"override"`
}

func proxyBackupPath() string { return pathIn("proxy-backup.json") }

func sysProxyEnable() error {
	k, err := registry.OpenKey(registry.CURRENT_USER, inetKey, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	if _, err := os.Stat(proxyBackupPath()); err != nil { // прежние значения — один раз
		var s savedProxy
		en, _, _ := k.GetIntegerValue("ProxyEnable")
		s.Enable = uint32(en)
		s.Server, _, _ = k.GetStringValue("ProxyServer")
		s.Override, _, _ = k.GetStringValue("ProxyOverride")
		b, _ := json.Marshal(s)
		_ = os.WriteFile(proxyBackupPath(), b, 0o600)
	}
	if err := k.SetStringValue("ProxyServer", "http=127.0.0.1:10809;https=127.0.0.1:10809;socks=127.0.0.1:10808"); err != nil {
		return err
	}
	_ = k.SetStringValue("ProxyOverride", "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>")
	if err := k.SetDWordValue("ProxyEnable", 1); err != nil {
		return err
	}
	notifyInet()
	return nil
}

func sysProxyDisable() error {
	k, err := registry.OpenKey(registry.CURRENT_USER, inetKey, registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer k.Close()
	s := savedProxy{}
	if b, err := os.ReadFile(proxyBackupPath()); err == nil {
		_ = json.Unmarshal(b, &s)
	}
	_ = k.SetDWordValue("ProxyEnable", s.Enable)
	if s.Server != "" {
		_ = k.SetStringValue("ProxyServer", s.Server)
	} else {
		_ = k.DeleteValue("ProxyServer")
	}
	if s.Override != "" {
		_ = k.SetStringValue("ProxyOverride", s.Override)
	}
	_ = os.Remove(proxyBackupPath())
	notifyInet()
	return nil
}

// Остался ли наш прокси с прошлого запуска (приложение убили) — тогда снять при старте.
func sysProxyLeftover() bool {
	_, err := os.Stat(proxyBackupPath())
	return err == nil
}

func notifyInet() {
	dll := windows.NewLazySystemDLL("wininet.dll")
	p := dll.NewProc("InternetSetOptionW")
	if p.Find() != nil {
		return
	}
	const settingsChanged, refresh = 39, 37
	_, _, _ = p.Call(0, settingsChanged, 0, 0)
	_, _, _ = p.Call(0, refresh, 0, 0)
}
