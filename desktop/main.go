// Бупень для Windows и Linux: клиент «Сети WYX». Один исполняемый файл:
//   bypen            — приложение (окно, ядро в режиме прокси, управление помощником);
//   bypen --helper … — помощник с правами администратора для режима TUN.
package main

import (
	"fmt"
	"net"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
)

var (
	quitCh   = make(chan struct{})
	quitOnce sync.Once
)

func requestQuit() { quitOnce.Do(func() { close(quitCh) }) }

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--helper" {
		helperMain(os.Args[2:])
		return
	}
	headless := len(os.Args) > 1 && os.Args[1] == "--headless" // проверка без окна (серверы, CI)
	// одна копия на пользователя
	lock, err := net.Listen("tcp", "127.0.0.1:10821")
	if err != nil {
		showError("Бупень уже запущен.")
		return
	}
	defer lock.Close()

	app := newApp()
	app.bootstrap()
	srv, err := startUIServer(app)
	if err != nil {
		showError("Не удалось запустить интерфейс: " + err.Error())
		return
	}
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	go func() { <-sig; requestQuit() }()
	tlog.Log("запуск %s, %s", version, platformTag())
	if headless {
		fmt.Println(srv.URL())
		if os.Getenv("BYPEN_AUTOCONNECT") != "" {
			runHeadlessCheck(app)
		}
		<-quitCh
	} else {
		runUI(srv.URL(), app)
	}
	app.Shutdown()
}

// Проверка для серверов: войти (BYPEN_USER/BYPEN_PASS или сохранённый вход), подключиться в
// режиме прокси (без изменений системы) и печатать состояние.
func runHeadlessCheck(app *App) {
	if u := os.Getenv("BYPEN_USER"); u != "" && !app.api.LoggedIn() {
		if err := app.Login(u, os.Getenv("BYPEN_PASS")); err != nil {
			fmt.Println("вход:", err)
			requestQuit()
			return
		}
	}
	app.refreshProfile(true)
	go func() {
		app.Connect(nil)
		for i := 0; i < 40; i++ {
			s := app.engine.Status()
			ms := "—"
			if s.LastProbeMs != nil {
				ms = fmt.Sprint(*s.LastProbeMs)
			}
			fmt.Printf("state=%s node=%s probe=%s fail=%d err=%s\n", s.State, s.NodeName, ms, s.Failures, strings.TrimSpace(s.LastError))
			if s.LastProbeMs != nil {
				break
			}
			if i == 39 {
				break
			}
			waitSec(1)
		}
		if os.Getenv("BYPEN_KEEP") == "" {
			requestQuit()
		}
	}()
}
