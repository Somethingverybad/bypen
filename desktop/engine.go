// Движок: ядро Xray (в процессе — режим прокси, в помощнике — режим TUN), проверка связи
// через socks и переключение узлов. Логика та же, что в расширении iPhone и на маке.
package main

import (
	"encoding/json"
	"os"
	"strings"
	"sync"
	"time"
)

type Status struct {
	State       string     `json:"state"` // stopped | starting | connected | switching | error
	NodeID      string     `json:"nodeId,omitempty"`
	NodeName    string     `json:"nodeName,omitempty"`
	Since       *time.Time `json:"since,omitempty"`
	Up          int64      `json:"up"`
	Down        int64      `json:"down"`
	LastProbeMs *int       `json:"lastProbeMs,omitempty"`
	Failures    int        `json:"failures"`
	Switches    int        `json:"switches"`
	LastError   string     `json:"lastError,omitempty"`
	Xray        string     `json:"xray,omitempty"`
	Mode        string     `json:"mode,omitempty"` // tun | proxy
}

type sample struct {
	at    time.Time
	bytes int64
}

type Engine struct {
	mu             sync.Mutex
	status         Status
	profile        *VpnProfile
	settings       Settings
	current        *VpnNode
	running        bool
	generation     int
	probeTimer     *time.Timer
	probeAttempt   int
	failures       int
	okOnThisNode   bool
	lastOkReport   time.Time
	lastOkLog      time.Time
	connectedAt    time.Time
	failedRecently map[string]time.Time
	samples        []sample
	runner         Runner
	tun            bool
	helper         *helperRunner
}

func newEngine() *Engine {
	return &Engine{status: Status{State: "stopped"}, failedRecently: map[string]time.Time{}, helper: &helperRunner{}}
}

func (e *Engine) Status() Status {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.status
}

func (e *Engine) Running() bool { e.mu.Lock(); defer e.mu.Unlock(); return e.running }

func (e *Engine) Start(preferred *string) {
	go e.start(preferred)
}

func (e *Engine) start(preferred *string) {
	e.mu.Lock()
	if e.running {
		e.mu.Unlock()
		return
	}
	ver := xrayVersion()
	tlog.Log("старт, Xray %s", ver)
	p := loadSavedProfile()
	if p == nil || len(p.Nodes) == 0 {
		e.status = Status{State: "stopped", LastError: "Нет профиля — обновите список узлов"}
		e.mu.Unlock()
		return
	}
	e.profile = p
	e.settings = loadSettings()
	e.tun = e.settings.Tun
	if e.tun {
		e.runner = e.helper
	} else {
		e.runner = &localRunner{}
	}
	e.running = true
	mode := "proxy"
	if e.tun {
		mode = "tun"
	}
	e.status = Status{State: "starting", Xray: ver, Mode: mode}
	order := p.order(preferredOr(preferred, e.settings.PreferredNode))
	e.mu.Unlock()

	node := e.startFirstAvailable(order)
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.running { // нажали «Отключить», пока поднимались
		return
	}
	if node == nil {
		e.failLocked("Ни один узел не запустился" + e.lastStartErr())
		return
	}
	if !e.tun && os.Getenv("BYPEN_NO_SYSPROXY") == "" {
		if err := sysProxyEnable(e.profile.directList()); err != nil {
			e.runner.Stop()
			e.failLocked("Не удалось включить системный прокси: " + err.Error())
			return
		}
		tlog.Log("системный прокси включён (HTTP %d, SOCKS %d)", httpPort, socksPort)
	} else {
		tlog.Log("TUN поднят (%s): весь трафик через туннель", tunName())
	}
	e.becameLocked(*node)
	e.scheduleProbeLocked(1500 * time.Millisecond)
}

var startErr string

func (e *Engine) lastStartErr() string {
	if startErr == "" {
		return ""
	}
	return ": " + startErr
}

func preferredOr(a, b *string) *string {
	if a != nil {
		return a
	}
	return b
}

func (e *Engine) startFirstAvailable(order []VpnNode) *VpnNode {
	startErr = ""
	for i := range order {
		n := order[i]
		e.mu.Lock()
		if !e.running {
			e.mu.Unlock()
			return nil
		}
		uuid, tun, r, direct := e.profile.User.UUID, e.tun, e.runner, e.profile.directList()
		e.mu.Unlock()
		if err := r.Run(buildXrayConfig(n, uuid, !tun, tun, direct)); err != nil {
			startErr = err.Error()
			tlog.Log("узел %s: ядро не запустилось — %v", n.Name, err)
			appendEvent(n.ID, false, nil, "start: "+trim(err.Error(), 150))
			// помощник не запустился (отказ в правах) — дальше пробовать бессмысленно
			if tun && (strings.Contains(err.Error(), "помощник") || strings.Contains(err.Error(), "отменено") || strings.Contains(err.Error(), "pkexec")) {
				return nil
			}
			continue
		}
		tlog.Log("узел %s (%s, %s:%d) — ядро запущено", n.Name, n.Kind, n.DialAddress(), n.Port)
		return &n
	}
	return nil
}

func (e *Engine) Stop(reason string) {
	e.mu.Lock()
	if !e.running {
		e.mu.Unlock()
		return
	}
	e.running = false
	e.generation++
	if e.probeTimer != nil {
		e.probeTimer.Stop()
	}
	tun, r := e.tun, e.runner
	e.current = nil
	e.status = Status{State: "stopped", Up: e.status.Up, Down: e.status.Down}
	e.mu.Unlock()
	tlog.Log("остановка (%s)", reason)
	if !tun && os.Getenv("BYPEN_NO_SYSPROXY") == "" {
		if err := sysProxyDisable(); err != nil {
			tlog.Log("системный прокси не выключился: %v", err)
		}
	}
	if r != nil {
		r.Stop()
	}
}

// Shutdown — при выходе: остановить и закрыть помощника.
func (e *Engine) Shutdown() {
	e.Stop("выход")
	e.helper.Quit()
}

func (e *Engine) failLocked(msg string) {
	tlog.Log("%s", msg)
	if !e.tun && os.Getenv("BYPEN_NO_SYSPROXY") == "" {
		_ = sysProxyDisable()
	}
	e.running = false
	e.status = Status{State: "stopped", LastError: msg}
}

func (e *Engine) becameLocked(n VpnNode) {
	now := time.Now()
	e.current = &n
	e.connectedAt = now
	e.okOnThisNode = false
	e.failures = 0
	e.probeAttempt = 0
	e.samples = nil
	e.status.State = "connected"
	e.status.NodeID = n.ID
	e.status.NodeName = n.Name
	e.status.Since = &now
	e.status.LastProbeMs = nil
	e.status.Failures = 0
	e.status.LastError = ""
}

func (e *Engine) SwitchNow(id *string) { go e.switchNode(id, "по команде") }

func (e *Engine) switchNode(id *string, reason string) {
	e.mu.Lock()
	if !e.running {
		e.mu.Unlock()
		return
	}
	if fresh := loadSavedProfile(); fresh != nil {
		e.profile = fresh
	}
	e.settings = loadSettings()
	p, cur := e.profile, e.current
	var candidates []VpnNode
	if id != nil {
		if n := p.node(*id); n != nil {
			candidates = []VpnNode{*n}
		} else {
			tlog.Log("узла %s нет в профиле", *id)
			e.mu.Unlock()
			return
		}
	} else {
		now := time.Now()
		var fresh, stale []VpnNode
		var okFirst []VpnNode
		for _, n := range p.Nodes {
			if cur != nil && n.ID == cur.ID {
				continue
			}
			okFirst = append(okFirst, n)
		}
		// живые раньше неживых, недавно упавшие — в конец
		var alive, dead []VpnNode
		for _, n := range okFirst {
			if n.OK {
				alive = append(alive, n)
			} else {
				dead = append(dead, n)
			}
		}
		for _, n := range append(alive, dead...) {
			if t, ok := e.failedRecently[n.ID]; ok && now.Sub(t) < 10*time.Minute {
				stale = append(stale, n)
			} else {
				fresh = append(fresh, n)
			}
		}
		candidates = append(fresh, stale...)
	}
	if len(candidates) == 0 {
		tlog.Log("переключаться некуда")
		e.mu.Unlock()
		return
	}
	e.generation++
	if e.probeTimer != nil {
		e.probeTimer.Stop()
	}
	e.status.State = "switching"
	if cur != nil && !strings.Contains(reason, "команде") && !strings.Contains(reason, "ротация") {
		e.failedRecently[cur.ID] = time.Now()
	}
	uuid, tun, r, direct := p.User.UUID, e.tun, e.runner, p.directList()
	e.mu.Unlock()

	for _, next := range candidates {
		if err := r.Run(buildXrayConfig(next, uuid, !tun, tun, direct)); err != nil {
			tlog.Log("узел %s: ядро не запустилось — %v", next.Name, err)
			e.mu.Lock()
			e.failedRecently[next.ID] = time.Now()
			e.mu.Unlock()
			continue
		}
		e.mu.Lock()
		if !e.running {
			e.mu.Unlock()
			r.Stop()
			return
		}
		name := "—"
		if cur != nil {
			name = cur.Name
		}
		tlog.Log("переключение: %s → %s (%s)", name, next.Name, reason)
		e.status.Switches++
		e.becameLocked(next)
		e.scheduleProbeLocked(1500 * time.Millisecond)
		e.mu.Unlock()
		return
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if cur != nil && r.Run(buildXrayConfig(*cur, uuid, !tun, tun, direct)) == nil {
		tlog.Log("остаёмся на %s", cur.Name)
		e.becameLocked(*cur)
	} else {
		e.status.State = "error"
		e.status.LastError = "Ни один узел не запустился"
	}
	e.scheduleProbeLocked(5 * time.Second)
}

func (e *Engine) ProbeNow() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.scheduleProbeLocked(0)
}

func (e *Engine) scheduleProbeLocked(d time.Duration) {
	if !e.running {
		return
	}
	if e.probeTimer != nil {
		e.probeTimer.Stop()
	}
	gen := e.generation
	e.probeTimer = time.AfterFunc(d, func() { e.runProbe(gen) })
}

func (e *Engine) runProbe(gen int) {
	e.mu.Lock()
	if gen != e.generation || !e.running || e.current == nil {
		e.mu.Unlock()
		return
	}
	node, attempt := *e.current, e.probeAttempt
	e.mu.Unlock()
	r := probe(attempt, 8*time.Second)
	e.refreshTraffic()
	e.mu.Lock()
	if gen != e.generation || !e.running {
		e.mu.Unlock()
		return
	}
	if r.OK {
		first := !e.okOnThisNode
		e.okOnThisNode, e.failures, e.probeAttempt = true, 0, 0
		delete(e.failedRecently, node.ID)
		ms := r.Ms
		e.status.State, e.status.LastProbeMs, e.status.Failures, e.status.LastError = "connected", &ms, 0, ""
		if first || time.Since(e.lastOkLog) > 10*time.Minute {
			tlog.Log("связь через %s: %d мс", node.Name, r.Ms)
			e.lastOkLog = time.Now()
		}
		if first || time.Since(e.lastOkReport) > 5*time.Minute {
			appendEvent(node.ID, true, &ms, "")
			e.lastOkReport = time.Now()
		}
		if e.maybeRotateIdleLocked() {
			e.mu.Unlock()
			go e.switchNode(nil, "ротация в простое")
			return
		}
		e.scheduleProbeLocked(20 * time.Second)
		e.mu.Unlock()
		return
	}
	e.failures++
	e.probeAttempt++
	e.status.Failures, e.status.LastError = e.failures, r.Error
	tlog.Log("проверка через %s не прошла (%d): %s", node.Name, e.failures, r.Error)
	limit := 2
	if e.okOnThisNode {
		limit = 3
	}
	if e.failures >= limit {
		appendEvent(node.ID, false, nil, trim(r.Error, 150))
		if e.settings.AutoSwitch && e.profile != nil && len(e.profile.Nodes) > 1 {
			e.mu.Unlock()
			e.switchNode(nil, "узел не отвечает")
			return
		}
		e.status.State = "error"
		e.scheduleProbeLocked(10 * time.Second)
		e.mu.Unlock()
		return
	}
	d := 3 * time.Second
	if e.okOnThisNode {
		d = 5 * time.Second
	}
	e.scheduleProbeLocked(d)
	e.mu.Unlock()
}

func (e *Engine) refreshTraffic() {
	e.mu.Lock()
	r := e.runner
	e.mu.Unlock()
	if r == nil {
		return
	}
	up, down := r.Traffic()
	e.mu.Lock()
	e.status.Up, e.status.Down = up, down
	e.samples = append(e.samples, sample{time.Now(), up + down})
	if len(e.samples) > 60 {
		e.samples = e.samples[len(e.samples)-60:]
	}
	e.mu.Unlock()
}

// Ротация в простое: давно на одном узле, за 10 минут меньше 300 КБ, есть другой живой.
func (e *Engine) maybeRotateIdleLocked() bool {
	s := e.settings
	if !s.RotateIdle || e.current == nil || e.profile == nil {
		return false
	}
	if time.Since(e.connectedAt) < time.Duration(s.RotateMinutes)*time.Minute {
		return false
	}
	var old *sample
	for i := range e.samples {
		if time.Since(e.samples[i].at) >= 10*time.Minute {
			old = &e.samples[i]
		}
	}
	if old == nil || len(e.samples) == 0 || e.samples[len(e.samples)-1].bytes-old.bytes >= 300*1024 {
		return false
	}
	for _, n := range e.profile.Nodes {
		if n.ID != e.current.ID && n.OK {
			return true
		}
	}
	return false
}

func trim(s string, n int) string {
	if len([]rune(s)) <= n {
		return s
	}
	return string([]rune(s)[:n])
}

// ---- события для POST /api/vpn/report/ ----

var eventsMu sync.Mutex

func appendEvent(node string, ok bool, rtt *int, errText string) {
	ev := map[string]any{"node": node, "ok": ok, "at": time.Now().UTC().Format(time.RFC3339), "net": platformTag()}
	if rtt != nil {
		ev["rtt_ms"] = *rtt
	}
	if errText != "" {
		ev["error"] = errText
	}
	b, _ := json.Marshal(ev)
	eventsMu.Lock()
	defer eventsMu.Unlock()
	f, err := os.OpenFile(eventsPath(), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.Write(append(b, '\n'))
}

func takeEvents() ([]map[string]any, func()) {
	eventsMu.Lock()
	b, _ := os.ReadFile(eventsPath())
	eventsMu.Unlock()
	var out []map[string]any
	for _, line := range strings.Split(string(b), "\n") {
		var m map[string]any
		if json.Unmarshal([]byte(line), &m) == nil {
			out = append(out, m)
		}
	}
	consumed := len(b)
	return out, func() {
		eventsMu.Lock()
		defer eventsMu.Unlock()
		cur, _ := os.ReadFile(eventsPath())
		if len(cur) >= consumed {
			_ = os.WriteFile(eventsPath(), cur[consumed:], 0o600)
		}
	}
}
