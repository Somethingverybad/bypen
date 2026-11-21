// Настройки: те же, что на телефонах, плюс режим (TUN или системный прокси).
package main

import (
	"encoding/json"
	"os"
)

type Settings struct {
	AutoSwitch    bool    `json:"autoSwitch"`
	RotateIdle    bool    `json:"rotateIdle"`
	RotateMinutes int     `json:"rotateMinutes"`
	PreferredNode *string `json:"preferredNode"`
	Tun           bool    `json:"tun"`
	Appearance    string  `json:"appearance"`
	V             int     `json:"v"`
}

func defaultSettings() Settings {
	return Settings{AutoSwitch: true, RotateIdle: true, RotateMinutes: 60, Tun: true, Appearance: "dark", V: 2}
}

func loadSettings() Settings {
	s := defaultSettings()
	b, err := os.ReadFile(settingsPath())
	if err != nil {
		return s
	}
	_ = json.Unmarshal(b, &s)
	if s.RotateMinutes <= 0 {
		s.RotateMinutes = 60
	}
	if s.Appearance != "light" {
		s.Appearance = "dark"
	}
	s.V = 2
	return s
}

func (s Settings) save() {
	b, _ := json.MarshalIndent(s, "", " ")
	_ = os.WriteFile(settingsPath(), b, 0o600)
}
