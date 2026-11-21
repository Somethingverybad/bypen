// Помощник с правами администратора: держит ядро Xray с входом TUN (создать интерфейс и
// поставить маршруты может только он). Приложение говорит с ним строками JSON по
// 127.0.0.1:helperPort, каждая команда несёт токен из файла, который знает только
// пользователь. Приложение исчезло — помощник всё снимает и выходит.
package main

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const helperPort = 10820

type helperCmd struct {
	Token  string `json:"token"`
	Cmd    string `json:"cmd"`
	Config string `json:"config,omitempty"`
	Tun    bool   `json:"tun,omitempty"`
}

type helperReply struct {
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
	Up    int64  `json:"up,omitempty"`
	Down  int64  `json:"down,omitempty"`
	Pid   int    `json:"pid,omitempty"`
}

func helperMain(args []string) {
	var tokenFile, logFile string
	parent := 0
	for i := 0; i+1 < len(args); i++ {
		switch args[i] {
		case "--token-file":
			tokenFile = args[i+1]
		case "--parent":
			parent, _ = strconv.Atoi(args[i+1])
		case "--log":
			logFile = args[i+1]
		}
	}
	hlog := func(f string, a ...any) {
		if logFile == "" {
			return
		}
		if fh, err := os.OpenFile(logFile, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644); err == nil {
			fmt.Fprintf(fh, "%s %s\n", time.Now().Format("15:04:05"), fmt.Sprintf(f, a...))
			fh.Close()
		}
	}
	tb, err := os.ReadFile(tokenFile)
	token := strings.TrimSpace(string(tb))
	if err != nil || len(token) < 16 {
		hlog("нет токена: %v", err)
		os.Exit(2)
	}
	if err := prepareTunDriver(); err != nil {
		hlog("драйвер TUN: %v", err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:"+strconv.Itoa(helperPort))
	if err != nil {
		hlog("не могу слушать: %v", err)
		os.Exit(1)
	}
	hlog("помощник запущен, приложение %d", parent)
	r := &localRunner{}
	var mu sync.Mutex
	tunUp := false
	shutdown := func(why string) {
		mu.Lock()
		if tunUp {
			afterTunDown()
		}
		r.Stop()
		mu.Unlock()
		hlog("выход: %s", why)
		os.Exit(0)
	}
	go func() {
		for parent > 0 {
			time.Sleep(time.Second)
			if !processAlive(parent) {
				shutdown("приложение завершилось")
			}
		}
	}()
	handle := func(c helperCmd) helperReply {
		if c.Token != token {
			return helperReply{Error: "токен"}
		}
		switch c.Cmd {
		case "ping":
			return helperReply{OK: true, Pid: os.Getpid()}
		case "run":
			mu.Lock()
			defer mu.Unlock()
			if tunUp {
				afterTunDown()
				tunUp = false
			}
			if err := r.Run(c.Config); err != nil {
				hlog("ядро: %v", err)
				return helperReply{Error: err.Error()}
			}
			if c.Tun {
				tunUp = true
				if err := afterTunUp(); err != nil {
					hlog("DNS: %v", err)
				}
			}
			hlog("ядро запущено (tun=%v)", c.Tun)
			return helperReply{OK: true}
		case "stop":
			mu.Lock()
			defer mu.Unlock()
			if tunUp {
				afterTunDown()
				tunUp = false
			}
			r.Stop()
			hlog("ядро остановлено")
			return helperReply{OK: true}
		case "traffic":
			u, d := r.Traffic()
			return helperReply{OK: true, Up: u, Down: d}
		case "quit":
			go func() { time.Sleep(200 * time.Millisecond); shutdown("по команде") }()
			return helperReply{OK: true}
		}
		return helperReply{Error: "неизвестная команда"}
	}
	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go func(conn net.Conn) {
			defer conn.Close()
			sc := bufio.NewScanner(conn)
			sc.Buffer(make([]byte, 64*1024), 4<<20)
			for sc.Scan() {
				var c helperCmd
				rep := helperReply{Error: "плохой запрос"}
				if json.Unmarshal(sc.Bytes(), &c) == nil {
					rep = handle(c)
				}
				b, _ := json.Marshal(rep)
				_, _ = conn.Write(append(b, '\n'))
			}
		}(conn)
	}
}

// ---- сторона приложения ----

type helperRunner struct {
	mu    sync.Mutex
	token string
}

func (h *helperRunner) tokenFile() string { return pathIn("helper.token") }

func (h *helperRunner) send(c helperCmd, timeout time.Duration) (*helperReply, error) {
	c.Token = h.token
	conn, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(helperPort), 2*time.Second)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(timeout))
	b, _ := json.Marshal(c)
	if _, err := conn.Write(append(b, '\n')); err != nil {
		return nil, err
	}
	sc := bufio.NewScanner(conn)
	sc.Buffer(make([]byte, 64*1024), 1<<20)
	if !sc.Scan() {
		return nil, errors.New("помощник не ответил")
	}
	var rep helperReply
	if err := json.Unmarshal(sc.Bytes(), &rep); err != nil {
		return nil, err
	}
	if !rep.OK {
		return &rep, errors.New(rep.Error)
	}
	return &rep, nil
}

// ensure — запустить помощника, если он ещё не отвечает (спросит права администратора).
func (h *helperRunner) ensure() error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.token != "" {
		if _, err := h.send(helperCmd{Cmd: "ping"}, 3*time.Second); err == nil {
			return nil
		}
	}
	b := make([]byte, 24)
	_, _ = rand.Read(b)
	h.token = hex.EncodeToString(b)
	if err := os.WriteFile(h.tokenFile(), []byte(h.token), 0o600); err != nil {
		return err
	}
	// файл журнала ядра создаём от пользователя — помощник будет в него дописывать
	if f, err := os.OpenFile(xrayLogPath(), os.O_CREATE|os.O_WRONLY, 0o600); err == nil {
		f.Close()
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	args := []string{"--helper", "--token-file", h.tokenFile(), "--parent", strconv.Itoa(os.Getpid()), "--log", helperLogPath()}
	if err := launchElevated(exe, args); err != nil {
		return err
	}
	for i := 0; i < 60; i++ {
		if _, err := h.send(helperCmd{Cmd: "ping"}, 2*time.Second); err == nil {
			return nil
		}
		time.Sleep(250 * time.Millisecond)
	}
	return errors.New("помощник не ответил за 15 с (журнал: " + helperLogPath() + ")")
}

func (h *helperRunner) Run(config string) error {
	if err := h.ensure(); err != nil {
		return err
	}
	_, err := h.send(helperCmd{Cmd: "run", Config: config, Tun: true}, 30*time.Second)
	return err
}

func (h *helperRunner) Stop() {
	if h.token != "" {
		_, _ = h.send(helperCmd{Cmd: "stop"}, 15*time.Second)
	}
}

func (h *helperRunner) Traffic() (int64, int64) {
	if h.token == "" {
		return 0, 0
	}
	r, err := h.send(helperCmd{Cmd: "traffic"}, 3*time.Second)
	if err != nil {
		return 0, 0
	}
	return r.Up, r.Down
}

func (h *helperRunner) Quit() {
	if h.token != "" {
		_, _ = h.send(helperCmd{Cmd: "quit"}, 3*time.Second)
	}
}

func helperLogPath() string { return pathIn("helper.log") }
