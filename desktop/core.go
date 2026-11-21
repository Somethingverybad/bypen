// Ядро Xray внутри процесса (режим прокси) или внутри помощника с правами администратора
// (режим TUN). Снаружи — одинаковый интерфейс: запустить конфиг, остановить, трафик.
package main

import (
	"fmt"
	"strings"
	"sync"

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
)

type Runner interface {
	Run(config string) error
	Stop()
	Traffic() (up, down int64)
}

func xrayVersion() string { return core.Version() }

type localRunner struct {
	mu   sync.Mutex
	inst *core.Instance
	// трафик прошлых запусков: ядро перезапускается при каждом переключении узла
	baseUp, baseDown int64
}

func (r *localRunner) Run(config string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.stopLocked()
	cfg, err := serial.LoadJSONConfig(strings.NewReader(config))
	if err != nil {
		return fmt.Errorf("конфиг: %w", err)
	}
	inst, err := core.New(cfg)
	if err != nil {
		return err
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		return err
	}
	r.inst = inst
	return nil
}

func (r *localRunner) Stop() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.stopLocked()
}

func (r *localRunner) stopLocked() {
	if r.inst == nil {
		return
	}
	u, d := r.countersLocked()
	r.baseUp += u
	r.baseDown += d
	_ = r.inst.Close()
	r.inst = nil
}

func (r *localRunner) countersLocked() (int64, int64) {
	if r.inst == nil {
		return 0, 0
	}
	m, ok := r.inst.GetFeature(stats.ManagerType()).(stats.Manager)
	if !ok || m == nil {
		return 0, 0
	}
	var up, down int64
	if c := m.GetCounter("outbound>>>proxy>>>traffic>>>uplink"); c != nil {
		up = c.Value()
	}
	if c := m.GetCounter("outbound>>>proxy>>>traffic>>>downlink"); c != nil {
		down = c.Value()
	}
	return up, down
}

func (r *localRunner) Traffic() (int64, int64) {
	r.mu.Lock()
	defer r.mu.Unlock()
	u, d := r.countersLocked()
	return r.baseUp + u, r.baseDown + d
}
