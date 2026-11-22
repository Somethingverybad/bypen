// Связь с сервером WYX: вход по аккаунту мессенджера (JWT), профиль узлов, отчёты.
package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type APIError struct {
	Msg          string
	Unauthorized bool
}

func (e *APIError) Error() string { return e.Msg }

type authState struct {
	Access   string `json:"access,omitempty"`
	Refresh  string `json:"refresh,omitempty"`
	Username string `json:"username,omitempty"`
	DeviceID string `json:"deviceId,omitempty"`
}

type API struct {
	mu   sync.Mutex
	st   authState
	http *http.Client
}

func newAPI() *API {
	a := &API{http: &http.Client{Timeout: 20 * time.Second}}
	a.load()
	if a.st.DeviceID == "" {
		b := make([]byte, 16)
		_, _ = rand.Read(b)
		a.st.DeviceID = "bypen-" + hex.EncodeToString(b)
		a.save()
	}
	return a
}

// Токены лежат зашифрованными (Windows — DPAPI пользователя), файл только для владельца.
func (a *API) load() {
	b, err := os.ReadFile(statePath())
	if err != nil {
		return
	}
	if plain, err := unprotect(b); err == nil {
		b = plain
	}
	_ = json.Unmarshal(b, &a.st)
}

func (a *API) save() {
	b, _ := json.Marshal(a.st)
	if enc, err := protect(b); err == nil {
		b = enc
	}
	_ = os.WriteFile(statePath(), b, 0o600)
}

func (a *API) LoggedIn() bool   { a.mu.Lock(); defer a.mu.Unlock(); return a.st.Refresh != "" }
func (a *API) Username() string { a.mu.Lock(); defer a.mu.Unlock(); return a.st.Username }

func appTag() string { return platformTag() + " " + version }

func (a *API) Login(username, password string) error {
	body := map[string]any{
		"username": username, "password": password,
		"device_id": a.st.DeviceID, "device_name": deviceName(),
		"platform": platformTag(), "app_version": version,
	}
	code, obj, err := a.send("token/", "POST", body, false)
	if err != nil {
		return err
	}
	acc, _ := obj["access"].(string)
	ref, _ := obj["refresh"].(string)
	if code != 200 || acc == "" || ref == "" {
		return &APIError{Msg: detail(obj, fmt.Sprintf("Не удалось войти (%d)", code))}
	}
	a.mu.Lock()
	a.st.Access, a.st.Refresh, a.st.Username = acc, ref, username
	a.save()
	a.mu.Unlock()
	return nil
}

// Вход через бота в WYX (сервер: chat/bypen_login.py).

const wyxDownloads = "https://wyx.su/#download"

type botLoginRequest struct {
	ID, Secret, Bot     string
	ExpiresIn, Interval int
}

var errBotDenied = &APIError{Msg: "Вход отклонён в WYX"}
var errBotExpired = &APIError{Msg: "Запрос устарел — попробуйте ещё раз"}

// StartBotLogin — бот «Бупень» пишет человеку в WYX «Подтвердить вход?».
func (a *API) StartBotLogin(username string) (*botLoginRequest, error) {
	body := map[string]any{
		"username": username, "device_id": a.st.DeviceID, "device_name": deviceName(),
		"platform": platformTag(), "app_version": version,
	}
	code, obj, err := a.send("vpn/login/start/", "POST", body, false)
	if err != nil {
		return nil, err
	}
	id, _ := obj["id"].(string)
	secret, _ := obj["secret"].(string)
	if code != 200 || id == "" || secret == "" {
		return nil, &APIError{Msg: detail(obj, fmt.Sprintf("Не удалось отправить запрос (%d)", code))}
	}
	r := &botLoginRequest{ID: id, Secret: secret, Bot: "Бупень", ExpiresIn: 300, Interval: 2}
	if b, ok := obj["bot"].(string); ok && b != "" {
		r.Bot = b
	}
	if v, ok := obj["expires_in"].(float64); ok && v > 0 {
		r.ExpiresIn = int(v)
	}
	if v, ok := obj["interval"].(float64); ok && v >= 1 {
		r.Interval = int(v)
	}
	return r, nil
}

// WaitBotLogin ждёт «Да» в WYX; закрытие cancel прерывает. Сбои сети по пути — спрашиваем снова.
func (a *API) WaitBotLogin(r *botLoginRequest, cancel <-chan struct{}) error {
	deadline := time.Now().Add(time.Duration(r.ExpiresIn+10) * time.Second)
	for time.Now().Before(deadline) {
		select {
		case <-cancel:
			return errBotCancelled
		case <-time.After(time.Duration(r.Interval) * time.Second):
		}
		code, obj, err := a.send("vpn/login/poll/", "POST", map[string]any{"id": r.ID, "secret": r.Secret}, false)
		if err != nil {
			continue
		}
		if code == 404 {
			return errBotExpired
		}
		if code != 200 {
			continue
		}
		switch obj["status"] {
		case "approved":
			acc, _ := obj["access"].(string)
			ref, _ := obj["refresh"].(string)
			user, _ := obj["username"].(string)
			if acc == "" || ref == "" {
				return errBotExpired
			}
			a.mu.Lock()
			a.st.Access, a.st.Refresh, a.st.Username = acc, ref, user
			a.save()
			a.mu.Unlock()
			return nil
		case "denied":
			return errBotDenied
		case "expired", "used":
			return errBotExpired
		}
	}
	return errBotExpired
}

var errBotCancelled = errors.New("отменено")

func (a *API) Logout() {
	a.mu.Lock()
	a.st.Access, a.st.Refresh, a.st.Username = "", "", ""
	a.save()
	a.mu.Unlock()
}

func (a *API) refreshTokens() error {
	a.mu.Lock()
	r := a.st.Refresh
	a.mu.Unlock()
	if r == "" {
		return &APIError{Msg: "Нужно войти", Unauthorized: true}
	}
	code, obj, err := a.send("token/refresh/", "POST", map[string]any{"refresh": r}, false)
	if err != nil {
		return err
	}
	acc, _ := obj["access"].(string)
	if code != 200 || acc == "" {
		if code == 401 || code == 400 {
			a.Logout()
			return &APIError{Msg: "Сеанс истёк — войдите снова", Unauthorized: true}
		}
		return &APIError{Msg: detail(obj, fmt.Sprintf("Не удалось обновить сеанс (%d)", code))}
	}
	a.mu.Lock()
	a.st.Access = acc
	if nr, ok := obj["refresh"].(string); ok && nr != "" {
		a.st.Refresh = nr
	}
	a.save()
	a.mu.Unlock()
	return nil
}

type signedProfile struct{ Payload, Sig, Pub string }

func (a *API) FetchProfile() (*signedProfile, error) {
	code, obj, err := a.authorized("vpn/profile/", "GET", nil)
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, &APIError{Msg: detail(obj, fmt.Sprintf("Профиль не получен (%d)", code))}
	}
	p, ok := obj["payload"].(string)
	if !ok {
		return nil, &APIError{Msg: "Профиль в неожиданном виде"}
	}
	sig, _ := obj["sig"].(string)
	pub, _ := obj["pub"].(string)
	return &signedProfile{Payload: p, Sig: sig, Pub: pub}, nil
}

func (a *API) Report(events []map[string]any) (int, error) {
	code, obj, err := a.authorized("vpn/report/", "POST", map[string]any{"events": events})
	if err != nil {
		return 0, err
	}
	if code != 200 {
		return 0, &APIError{Msg: detail(obj, fmt.Sprintf("Отчёт не принят (%d)", code))}
	}
	n, _ := obj["saved"].(float64)
	return int(n), nil
}

func (a *API) authorized(path, method string, body any) (int, map[string]any, error) {
	a.mu.Lock()
	hasAccess := a.st.Access != ""
	a.mu.Unlock()
	if !hasAccess {
		if err := a.refreshTokens(); err != nil {
			return 0, nil, err
		}
	}
	code, obj, err := a.send(path, method, body, true)
	if err == nil && code == 401 {
		if err := a.refreshTokens(); err != nil {
			return 0, nil, err
		}
		code, obj, err = a.send(path, method, body, true)
		if err == nil && code == 401 {
			a.Logout()
			return 0, nil, &APIError{Msg: "Сеанс истёк — войдите снова", Unauthorized: true}
		}
	}
	return code, obj, err
}

func (a *API) send(path, method string, body any, auth bool) (int, map[string]any, error) {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, strings.TrimRight(apiBase, "/")+"/"+path, rd)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("X-WYX-App", appTag())
	req.Header.Set("User-Agent", "Bypen/"+version+" "+platformTag())
	if auth {
		a.mu.Lock()
		if a.st.Access != "" {
			req.Header.Set("Authorization", "Bearer "+a.st.Access)
		}
		a.mu.Unlock()
	}
	resp, err := a.http.Do(req)
	if err != nil {
		return 0, nil, &APIError{Msg: "Сервер недоступен: " + err.Error()}
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	var obj map[string]any
	_ = json.Unmarshal(data, &obj)
	return resp.StatusCode, obj, nil
}

func detail(obj map[string]any, fallback string) string {
	if obj != nil {
		if d, ok := obj["detail"].(string); ok && d != "" {
			return d
		}
		if d, ok := obj["error"].(string); ok && d != "" {
			return d
		}
		if l, ok := obj["non_field_errors"].([]any); ok && len(l) > 0 {
			parts := make([]string, 0, len(l))
			for _, x := range l {
				parts = append(parts, fmt.Sprint(x))
			}
			return strings.Join(parts, " ")
		}
	}
	return fallback
}

var errNotProtected = errors.New("not protected")
