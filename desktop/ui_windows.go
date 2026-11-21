//go:build windows

package main

import (
	_ "embed"
	"path/filepath"
	"time"
	"unsafe"

	"fyne.io/systray"
	"github.com/jchv/go-webview2"
	"golang.org/x/sys/windows"
)

//go:embed assets/icon.ico
var windowsTrayIcon []byte

// Идентификатор первой группы иконок в rsrc_windows_amd64.syso (scripts/resources.sh).
const windowsIconID = 1

// Окно на WebView2. Класс окна, панель задач и Проводник используют одну иконку EXE.
func runUI(url string, app *App) {
	id, _ := windows.UTF16PtrFromString("com.hyax.bypen.desktop")
	_, _, _ = windows.NewLazySystemDLL("shell32.dll").NewProc("SetCurrentProcessExplicitAppUserModelID").Call(uintptr(unsafe.Pointer(id)))
	w := webview2.NewWithOptions(webview2.WebViewOptions{
		AutoFocus: true,
		DataPath:  filepath.Join(appDir(), "webview"),
		WindowOptions: webview2.WindowOptions{
			Title: "Бупень", Width: 420, Height: 780, Center: true, IconId: windowsIconID,
		},
	})
	if w == nil { // Нет WebView2: интерфейс в браузере, выход доступен в трее.
		openExternal(url)
		systray.Run(func() { setupWindowsTray(app, func() { openExternal(url) }) }, func() {})
		requestQuit()
		return
	}
	w.SetSize(380, 640, webview2.HintMin)
	w.Navigate(url)
	show := func() {
		w.Dispatch(func() {
			u32 := windows.NewLazySystemDLL("user32.dll")
			hwnd := uintptr(w.Window())
			_, _, _ = u32.NewProc("ShowWindow").Call(hwnd, 9) // SW_RESTORE
			_, _, _ = u32.NewProc("SetForegroundWindow").Call(hwnd)
		})
	}
	// WebView2 уже обрабатывает сообщения Windows на этом потоке, второй цикл не нужен.
	systray.Register(func() { setupWindowsTray(app, show) }, func() {})
	go func() {
		<-quitCh
		w.Dispatch(func() { systray.Quit(); w.Terminate() })
	}()
	w.Run()
	requestQuit()
	systray.Quit()
	w.Destroy()
}

func setupWindowsTray(app *App, show func()) {
	systray.SetIcon(windowsTrayIcon)
	systray.SetTitle("Бупень")
	systray.SetTooltip("Бупень — сеть WYX")
	systray.SetOnTapped(show)
	mOpen := systray.AddMenuItem("Открыть Бупень", "")
	mToggle := systray.AddMenuItem("Подключить", "")
	systray.AddSeparator()
	mQuit := systray.AddMenuItem("Выйти", "")
	tick := time.NewTicker(time.Second)
	update := func() {
		if app.engine.Running() {
			mToggle.SetTitle("Отключить")
			mToggle.Enable()
		} else {
			mToggle.SetTitle("Подключить")
			if app.api.LoggedIn() {
				mToggle.Enable()
			} else {
				mToggle.Disable()
			}
		}
	}
	update()
	go func() {
		defer tick.Stop()
		for {
			select {
			case <-mOpen.ClickedCh:
				show()
			case <-mToggle.ClickedCh:
				if app.engine.Running() {
					go app.engine.Stop("из трея")
				} else {
					app.Connect(nil)
				}
			case <-mQuit.ClickedCh:
				requestQuit()
			case <-tick.C:
				update()
			case <-quitCh:
				systray.Quit()
				return
			}
		}
	}()
}

func openExternal(url string) {
	verb, _ := windows.UTF16PtrFromString("open")
	u, _ := windows.UTF16PtrFromString(url)
	_ = windows.ShellExecute(0, verb, u, nil, nil, windows.SW_SHOWNORMAL)
}

func showError(msg string) {
	t, _ := windows.UTF16PtrFromString("Бупень")
	m, _ := windows.UTF16PtrFromString(msg)
	_, _ = windows.MessageBox(0, m, t, windows.MB_OK|windows.MB_ICONWARNING)
}
