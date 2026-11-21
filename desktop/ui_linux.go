//go:build linux

package main

import (
	_ "embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"

	"fyne.io/systray"
)

//go:embed ui/icon.png
var trayIcon []byte

// Linux: окно — браузер на Chromium в режиме приложения (без вкладок), иначе браузер по
// умолчанию; значок в трее: открыть, подключить/отключить, выйти.
func runUI(url string, app *App) {
	openWindow := func() { openAppWindow(url) }
	openWindow()
	systray.Run(func() {
		systray.SetIcon(trayIcon)
		systray.SetTitle("Бупень")
		systray.SetTooltip("Бупень — сеть WYX")
		mOpen := systray.AddMenuItem("Открыть Бупень", "")
		mToggle := systray.AddMenuItem("Подключить", "")
		systray.AddSeparator()
		mQuit := systray.AddMenuItem("Выйти", "")
		go func() {
			for {
				select {
				case <-mOpen.ClickedCh:
					openWindow()
				case <-mToggle.ClickedCh:
					if app.engine.Running() {
						go app.engine.Stop("из трея")
					} else {
						app.Connect(nil)
					}
				case <-mQuit.ClickedCh:
					requestQuit()
				case <-quitCh:
					systray.Quit()
					return
				}
			}
		}()
		go func() {
			last := ""
			for {
				select {
				case <-quitCh:
					return
				default:
				}
				t := "Подключить"
				if app.engine.Running() {
					t = "Отключить"
				}
				if t != last {
					mToggle.SetTitle(t)
					last = t
				}
				waitSec(1)
			}
		}()
	}, func() {})
}

func openAppWindow(url string) {
	for _, b := range []string{"chromium", "chromium-browser", "google-chrome", "google-chrome-stable", "brave-browser", "microsoft-edge", "vivaldi"} {
		if p, err := exec.LookPath(b); err == nil {
			cmd := exec.Command(p, "--app="+url, "--class=Bypen", "--window-size=420,780",
				"--user-data-dir="+filepath.Join(appDir(), "browser"), "--no-first-run", "--no-default-browser-check")
			cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
			if cmd.Start() == nil {
				go cmd.Wait()
				return
			}
		}
	}
	openExternal(url)
}

func openExternal(url string) {
	cmd := exec.Command("xdg-open", url)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if cmd.Start() == nil {
		go cmd.Wait()
	}
}

func showError(msg string) {
	if p, err := exec.LookPath("notify-send"); err == nil {
		_ = exec.Command(p, "Бупень", msg).Run()
	}
	fmt.Fprintln(os.Stderr, msg)
}
