package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

// Вход через бота: запрос → ожидание → «Да» в WYX → токены сохранены.
func TestBotLoginApproved(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	var polls int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/vpn/login/start/":
			if body["username"] != "zz_test_a" || body["device_id"] == "" {
				w.WriteHeader(400)
				return
			}
			_, _ = w.Write([]byte(`{"id":"req-1","secret":"s3","expires_in":30,"interval":1,"bot":"Бупень"}`))
		case "/api/vpn/login/poll/":
			if body["secret"] != "s3" {
				w.WriteHeader(404)
				return
			}
			if atomic.AddInt32(&polls, 1) < 2 {
				_, _ = w.Write([]byte(`{"status":"pending"}`))
				return
			}
			_, _ = w.Write([]byte(`{"status":"approved","access":"A","refresh":"R","username":"zz_test_a"}`))
		default:
			w.WriteHeader(404)
		}
	}))
	defer srv.Close()
	apiBase = srv.URL + "/api"
	a := newAPI()
	r, err := a.StartBotLogin("zz_test_a")
	if err != nil || r.Bot != "Бупень" || r.Interval != 1 {
		t.Fatalf("start: %v %+v", err, r)
	}
	if err := a.WaitBotLogin(r, make(chan struct{})); err != nil {
		t.Fatalf("wait: %v", err)
	}
	if !a.LoggedIn() || a.Username() != "zz_test_a" || polls < 2 {
		t.Fatalf("после «Да»: loggedIn=%v user=%q polls=%d", a.LoggedIn(), a.Username(), polls)
	}
}

func TestBotLoginDeniedAndCancel(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"status":"denied"}`))
	}))
	defer srv.Close()
	apiBase = srv.URL + "/api"
	a := newAPI()
	req := &botLoginRequest{ID: "x", Secret: "y", ExpiresIn: 10, Interval: 1}
	if err := a.WaitBotLogin(req, make(chan struct{})); err != errBotDenied {
		t.Fatalf("ждали отказ, получили %v", err)
	}
	c := make(chan struct{})
	close(c)
	if err := a.WaitBotLogin(req, c); err != errBotCancelled {
		t.Fatalf("ждали отмену, получили %v", err)
	}
	if a.LoggedIn() {
		t.Fatal("после отказа вход не должен состояться")
	}
}

// Настройки «напрямую»: чтение и сохранение в профиле WYX.
func TestDirectSettingsRoundTrip(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	var saved map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/vpn/direct/" || r.Header.Get("Authorization") != "Bearer A" {
			w.WriteHeader(404)
			return
		}
		if r.Method == "PUT" {
			_ = json.NewDecoder(r.Body).Decode(&saved)
		}
		_, _ = w.Write([]byte(`{"ru":false,"custom":["example.com","full:api.foo.io"],"ru_count":49}`))
	}))
	defer srv.Close()
	apiBase = srv.URL + "/api"
	a := newAPI()
	a.st.Access, a.st.Refresh = "A", "R"
	d, err := a.FetchDirect()
	if err != nil || d.RU || d.RUCount != 49 || len(d.Custom) != 2 {
		t.Fatalf("fetch: %v %+v", err, d)
	}
	if _, err := a.SaveDirect(map[string]any{"ru": false}); err != nil || saved["ru"] != false {
		t.Fatalf("save: %v %v", err, saved)
	}
}

func TestBypassHostsAndRules(t *testing.T) {
	d := DirectList{Domains: []string{"ru", "example.com", "full:api.foo.io"}}
	got := d.bypassHosts("*.")
	want := []string{"ru", "*.ru", "example.com", "*.example.com", "api.foo.io"}
	if len(got) != len(want) {
		t.Fatalf("bypass: %v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("bypass: %v", got)
		}
	}
	rules := directRules(d)
	doms := rules[0].(map[string]any)["domain"].([]string)
	if doms[0] != "domain:ru" || doms[2] != "full:api.foo.io" {
		t.Fatalf("правила: %v", doms)
	}
}
