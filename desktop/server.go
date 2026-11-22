// Локальный сервер интерфейса: страница (ui/) и JSON-команды. Слушает только 127.0.0.1,
// каждая команда несёт случайный токен этого запуска, Host проверяется (от подмены DNS).
package main

import (
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"io/fs"
	"net"
	"net/http"
	"os"
	"strconv"
	"time"
)

//go:embed ui
var uiFS embed.FS

type uiServer struct {
	app   *App
	token string
	addr  string
}

func startUIServer(app *App) (*uiServer, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	s := &uiServer{app: app, token: hex.EncodeToString(b), addr: ln.Addr().String()}
	sub, _ := fs.Sub(uiFS, "ui")
	mux := http.NewServeMux()
	static := http.FileServer(http.FS(sub))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if !s.hostOK(r) {
			http.Error(w, "forbidden", 403)
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		static.ServeHTTP(w, r)
	})
	mux.HandleFunc("/api/", s.api)
	go func() { _ = http.Serve(ln, mux) }()
	return s, nil
}

func (s *uiServer) URL() string { return "http://" + s.addr + "/#" + s.token }

func (s *uiServer) hostOK(r *http.Request) bool { return r.Host == s.addr }

func (s *uiServer) api(w http.ResponseWriter, r *http.Request) {
	if !s.hostOK(r) || r.Header.Get("X-Bypen") != s.token {
		http.Error(w, "forbidden", 403)
		return
	}
	var body struct {
		Username string          `json:"username"`
		Password string          `json:"password"`
		Node     *string         `json:"node"`
		Settings json.RawMessage `json:"settings"`
		URL      string          `json:"url"`
	}
	if r.Method == http.MethodPost {
		_ = json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&body)
	}
	a := s.app
	reply := func(v any) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(v)
	}
	switch r.URL.Path {
	case "/api/state":
		reply(a.View())
	case "/api/login":
		err := a.Login(body.Username, body.Password)
		if err != nil {
			reply(map[string]any{"ok": false, "error": err.Error()})
			return
		}
		reply(map[string]any{"ok": true})
	case "/api/login/wyx":
		a.LoginViaWYX(body.Username)
		reply(map[string]any{"ok": true})
	case "/api/login/cancel":
		a.CancelBotLogin()
		reply(map[string]any{"ok": true})
	case "/api/wyx/download":
		openExternal(wyxDownloads)
		reply(map[string]any{"ok": true})
	case "/api/logout":
		a.Logout()
		reply(map[string]any{"ok": true})
	case "/api/connect":
		a.Connect(body.Node)
		reply(map[string]any{"ok": true})
	case "/api/disconnect":
		go a.engine.Stop("по кнопке")
		reply(map[string]any{"ok": true})
	case "/api/select":
		a.Select(body.Node)
		reply(map[string]any{"ok": true})
	case "/api/settings":
		cur := loadSettings()
		wasTun := cur.Tun
		_ = json.Unmarshal(body.Settings, &cur)
		if a.engine.Running() && cur.Tun != wasTun {
			cur.Tun = wasTun // режим меняется только в отключённом состоянии
		}
		cur.save()
		reply(map[string]any{"ok": true})
	case "/api/refresh":
		go a.refreshProfile(true)
		reply(map[string]any{"ok": true})
	case "/api/log":
		x, _ := os.ReadFile(xrayLogPath())
		reply(map[string]any{"log": tlog.Read(), "xray": tail(string(x), 6000)})
	case "/api/log/clear":
		tlog.Clear()
		reply(map[string]any{"ok": true})
	case "/api/open":
		if body.URL != "" && (len(body.URL) > 8 && body.URL[:8] == "https://") {
			openExternal(body.URL)
		}
		reply(map[string]any{"ok": true})
	case "/api/quit":
		reply(map[string]any{"ok": true})
		go func() { time.Sleep(150 * time.Millisecond); requestQuit() }()
	default:
		http.NotFound(w, r)
	}
}

var _ = strconv.Itoa
