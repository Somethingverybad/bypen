//go:build windows

package main

import (
	"encoding/binary"
	"testing"

	"golang.org/x/sys/windows"
)

// Проверяет реальные ресурсы PE: эти же размеры загружает оболочка Windows
// для панели задач, Alt+Tab и миниатюр файла, а не только иконку веб-страницы.
func TestWindowsIconResources(t *testing.T) {
	if len(windowsTrayIcon) < 6 || binary.LittleEndian.Uint16(windowsTrayIcon[2:4]) != 1 {
		t.Fatal("неверный формат иконки трея")
	}
	if count := binary.LittleEndian.Uint16(windowsTrayIcon[4:6]); count != 9 {
		t.Fatalf("размеры иконки: %d, ожидалось 9", count)
	}
	var module windows.Handle
	if err := windows.GetModuleHandleEx(0, nil, &module); err != nil {
		t.Fatal(err)
	}
	u32 := windows.NewLazySystemDLL("user32.dll")
	for _, size := range []uintptr{16, 20, 24, 32, 40, 48, 64, 128, 256} {
		icon, _, err := u32.NewProc("LoadImageW").Call(uintptr(module), windowsIconID, 1, size, size, 0)
		if icon == 0 {
			t.Fatalf("ресурс иконки %dx%d не загрузился: %v", size, size, err)
		}
		u32.NewProc("DestroyIcon").Call(icon)
	}
}
