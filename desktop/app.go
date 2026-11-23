// Состояние приложения: вход, профиль узлов (проверенный подписью), движок, отчёты, обновления.
package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

type UpdateInfo struct {
	Version string `json:"version"`
	URL     string `json:"url"`
	Notes   string `json:"notes"`
}

type App struct {
	mu               sync.Mutex
	api              *API
	engine           *Engine
	profile          *VpnProfile
	profileNote      string
	lastErr          string
	busy             bool
	lastProfileFetch time.Time
	update           *UpdateInfo
	quit             chan struct{}
	awaitingBot      string // ждём «Да» в WYX — имя бота
	direct           *DirectSettings
	directErr        string
	directPending    bool          // сохранили при включённом VPN — применится после переподключения
	directNote       string        // итог «Поделиться»
	botCancel        chan struct{} // закрыть — прервать ожидание
}

func newApp() *App {
	a := &App{api: newAPI(), engine: newEngine(), profile: loadSavedProfile(), quit: make(chan struct{})}
	if sysProxyLeftover() { // прошлый запуск убили, не сняв прокси
		_ = sysProxyDisable()
		tlog.Log("снят системный прокси, оставшийся с прошлого запуска")
	}
	return a
}

func (a *App) bootstrap() {
	go func() {
		a.refreshProfile(false)
		a.uploadEvents()
		a.checkUpdate()
		t := time.NewTicker(5 * time.Minute)
		for {
			select {
			case <-t.C:
				// в отличие от телефона, приложение на компьютере живёт долго — сами обновляем список
				a.refreshProfile(false)
				a.uploadEvents()
			case <-a.quit:
				return
			}
		}
	}()
}

func (a *App) setErr(s string) { a.mu.Lock(); a.lastErr = s; a.mu.Unlock() }

func (a *App) Login(u, p string) error {
	a.mu.Lock()
	a.busy = true
	a.mu.Unlock()
	defer func() { a.mu.Lock(); a.busy = false; a.mu.Unlock() }()
	if err := a.api.Login(strings.TrimSpace(u), p); err != nil {
		a.setErr(err.Error())
		return err
	}
	a.setErr("")
	tlog.Log("вход: %s", strings.TrimSpace(u))
	a.refreshProfile(true)
	return nil
}

// LoginViaWYX — вход без пароля: бот «Бупень» спрашивает в WYX «Подтвердить вход?».
func (a *App) LoginViaWYX(u string) {
	u = strings.TrimSpace(u)
	a.CancelBotLogin()
	cancel := make(chan struct{})
	a.mu.Lock()
	a.busy, a.lastErr, a.botCancel = true, "", cancel
	a.mu.Unlock()
	go func() {
		defer func() {
			a.mu.Lock()
			if a.botCancel == cancel {
				a.busy, a.awaitingBot, a.botCancel = false, "", nil
			}
			a.mu.Unlock()
		}()
		r, err := a.api.StartBotLogin(u)
		a.mu.Lock()
		current := a.botCancel == cancel
		if current && err == nil {
			a.awaitingBot = r.Bot
		}
		a.mu.Unlock()
		if !current {
			return
		}
		if err != nil {
			a.setErr(err.Error())
			return
		}
		tlog.Log("вход через WYX: запрос для %s", u)
		if err := a.api.WaitBotLogin(r, cancel); err != nil {
			if err != errBotCancelled {
				a.setErr(err.Error())
			}
			return
		}
		a.setErr("")
		tlog.Log("вход через WYX: подтверждён")
		a.refreshProfile(true)
	}()
}

// LoadDirect — настройки «напрямую» из профиля WYX.
func (a *App) LoadDirect() {
	d, err := a.api.FetchDirect()
	a.mu.Lock()
	defer a.mu.Unlock()
	if err != nil {
		a.directErr = err.Error()
		return
	}
	a.direct, a.directErr = d, ""
}

// SaveDirect сохраняет в профиль WYX и перечитывает список узлов; при включённом VPN
// новые правила применятся после переподключения (TUN снова попросит права администратора).
func (a *App) SaveDirect(body map[string]any) {
	d, err := a.api.SaveDirect(body)
	a.mu.Lock()
	if err != nil {
		a.directErr = err.Error()
		a.mu.Unlock()
		return
	}
	a.direct, a.directErr = d, ""
	a.mu.Unlock()
	tlog.Log("напрямую: российские %v, своих %d", d.RU, len(d.Custom))
	a.refreshProfile(true)
	if a.engine.Running() {
		a.mu.Lock()
		a.directPending = true
		a.mu.Unlock()
	}
}

// ShareDirect — поделиться настройками «напрямую» по логину WYX.
func (a *App) ShareDirect(username string) {
	u := strings.TrimLeft(strings.TrimSpace(username), "@")
	if u == "" {
		return
	}
	name, err := a.api.ShareDirect(u)
	a.mu.Lock()
	defer a.mu.Unlock()
	if err != nil {
		a.directErr = err.Error()
		return
	}
	a.directErr, a.directNote = "", "Отправлено @"+name+" — бот «Бупень» спросит, принять ли настройки"
}

// ReconnectDirect — переподключиться, чтобы применить список «напрямую».
func (a *App) ReconnectDirect() {
	node := a.engine.Status().NodeID
	a.engine.Stop("применить список «напрямую»")
	for i := 0; i < 40 && a.engine.Running(); i++ {
		time.Sleep(250 * time.Millisecond)
	}
	a.mu.Lock()
	a.directPending = false
	a.mu.Unlock()
	if node != "" {
		a.Connect(&node)
	} else {
		a.Connect(nil)
	}
}

func (a *App) CancelBotLogin() {
	a.mu.Lock()
	if a.botCancel != nil {
		close(a.botCancel)
		a.botCancel = nil
	}
	a.busy, a.awaitingBot = false, ""
	a.mu.Unlock()
}

func (a *App) Logout() {
	a.engine.Stop("выход из аккаунта")
	a.api.Logout()
	_ = os.Remove(profilePath())
	a.mu.Lock()
	a.profile = nil
	a.mu.Unlock()
	tlog.Log("выход")
}

func (a *App) refreshProfile(force bool) {
	if !a.api.LoggedIn() {
		return
	}
	a.mu.Lock()
	if !force && a.profile != nil && time.Since(a.lastProfileFetch) < time.Duration(max(a.profile.TTL, 60))*time.Second {
		a.mu.Unlock()
		return
	}
	a.mu.Unlock()
	s, err := a.api.FetchProfile()
	if err == nil {
		err = verifySignature(s.Payload, s.Sig, s.Pub)
	}
	var p *VpnProfile
	if err == nil {
		p, err = decodeProfile(s.Payload)
	}
	if err != nil {
		var ae *APIError
		if errors.As(err, &ae) && ae.Unauthorized {
			a.Logout()
		}
		a.setErr(err.Error())
		tlog.Log("профиль не обновлён: %v", err)
		return
	}
	_ = os.WriteFile(profilePath(), []byte(s.Payload), 0o600)
	a.mu.Lock()
	a.profile, a.lastProfileFetch, a.lastErr = p, time.Now(), ""
	a.mu.Unlock()
	alive := 0
	for _, n := range p.Nodes {
		if n.OK {
			alive++
		}
	}
	tlog.Log("профиль обновлён: узлов %d, живых %d", len(p.Nodes), alive)
}

func (a *App) Connect(node *string) {
	a.setErr("")
	if a.profileSnapshot() == nil {
		a.refreshProfile(true)
	}
	p := a.profileSnapshot()
	if p == nil || len(p.Nodes) == 0 {
		a.setErr("Нет узлов — доступ к сети WYX не выдан?")
		return
	}
	tlog.Log("подключение")
	a.engine.Start(node)
}

func (a *App) profileSnapshot() *VpnProfile { a.mu.Lock(); defer a.mu.Unlock(); return a.profile }

func (a *App) Select(id *string) {
	s := loadSettings()
	s.PreferredNode = id
	s.save()
	if a.engine.Running() {
		if id != nil {
			a.engine.SwitchNow(id)
		}
	}
}

func (a *App) uploadEvents() {
	if !a.api.LoggedIn() {
		return
	}
	evs, commit := takeEvents()
	if len(evs) == 0 {
		return
	}
	if len(evs) > 200 {
		evs = evs[len(evs)-200:]
	}
	if n, err := a.api.Report(evs); err == nil {
		commit()
		tlog.Log("отчёты отправлены: %d", n)
	}
}

// Обновления: манифест в бакете (installers/bypen/windows.json | linux.json), как у Android.
func (a *App) checkUpdate() {
	c := &http.Client{Timeout: 15 * time.Second}
	resp, err := c.Get(updateBase + platformTag() + ".json")
	if err != nil {
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return
	}
	var u UpdateInfo
	if json.NewDecoder(resp.Body).Decode(&u) != nil || u.URL == "" {
		return
	}
	if newer(u.Version, version) {
		a.mu.Lock()
		a.update = &u
		a.mu.Unlock()
		tlog.Log("есть обновление %s", u.Version)
	}
}

func newer(a, b string) bool {
	pa, pb := strings.Split(strings.SplitN(a, "-", 2)[0], "."), strings.Split(strings.SplitN(b, "-", 2)[0], ".")
	for i := 0; i < 3; i++ {
		var x, y int
		if i < len(pa) {
			x, _ = strconv.Atoi(pa[i])
		}
		if i < len(pb) {
			y, _ = strconv.Atoi(pb[i])
		}
		if x != y {
			return x > y
		}
	}
	return false
}

func (a *App) Shutdown() {
	select {
	case <-a.quit:
	default:
		close(a.quit)
	}
	a.engine.Shutdown()
}

// ---- снимок для интерфейса ----

type viewState struct {
	LoggedIn      bool            `json:"loggedIn"`
	Username      string          `json:"username"`
	Busy          bool            `json:"busy"`
	Error         string          `json:"error,omitempty"`
	ProfileNote   string          `json:"profileNote,omitempty"`
	Nodes         []VpnNode       `json:"nodes"`
	UUIDPrefix    string          `json:"uuidPrefix,omitempty"`
	Settings      Settings        `json:"settings"`
	Status        Status          `json:"status"`
	Running       bool            `json:"running"`
	Version       string          `json:"version"`
	Platform      string          `json:"platform"`
	Xray          string          `json:"xray"`
	Update        *UpdateInfo     `json:"update,omitempty"`
	AwaitingBot   string          `json:"awaitingBot,omitempty"`
	Direct        *DirectSettings `json:"direct,omitempty"`
	DirectError   string          `json:"directError,omitempty"`
	DirectPending bool            `json:"directPending,omitempty"`
	DirectNote    string          `json:"directNote,omitempty"`
}

func (a *App) View() viewState {
	a.mu.Lock()
	v := viewState{LoggedIn: a.api.st.Refresh != "", Username: a.api.st.Username, Busy: a.busy, Error: a.lastErr,
		ProfileNote: a.profileNote, Version: version, Platform: platformTag(), Xray: xrayVersion(), Update: a.update,
		AwaitingBot: a.awaitingBot, Direct: a.direct, DirectError: a.directErr, DirectPending: a.directPending && a.engine.Running(), DirectNote: a.directNote}
	if a.profile != nil {
		v.Nodes = a.profile.Nodes
		if len(a.profile.User.UUID) >= 8 {
			v.UUIDPrefix = a.profile.User.UUID[:8]
		}
	}
	a.mu.Unlock()
	if v.Nodes == nil {
		v.Nodes = []VpnNode{}
	}
	v.Settings = loadSettings()
	v.Status = a.engine.Status()
	v.Running = a.engine.Running()
	return v
}
