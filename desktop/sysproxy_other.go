//go:build !windows && !linux

package main

// На маке своё приложение; здесь — только для проверки ядра без изменения системы.
func sysProxyEnable() error  { return nil }
func sysProxyDisable() error { return nil }
func sysProxyLeftover() bool { return false }
