package main

import (
	"strings"
	"testing"
	"time"

	"github.com/xtls/xray-core/infra/conf/serial"
)

var testNodes = []VpnNode{
	{ID: "r", Name: "Reality", Kind: "reality", Host: "nemilf.hyax.ru", Port: 443, SNI: "dl.google.com",
		IPs: []string{"194.164.245.54"}, Pbk: "RGIRo2jp-XSIn4JnwQhovW-18UrUG4l_sE17da1uFVk", Sid: "0123abcd"},
	{ID: "x", Name: "XHTTP", Kind: "xhttp", Host: "nemilf.hyax.ru", Port: 443, SNI: "nemilf.hyax.ru",
		IPs: []string{"194.164.245.54"}, Path: "/vless-xhttp"},
}

// Конфиги с TUN разбираются ядром (сам интерфейс создаёт только помощник с правами).
func TestConfigsParse(t *testing.T) {
	for _, n := range testNodes {
		for _, tun := range []bool{false, true} {
			js := buildXrayConfig(n, "00000000-0000-4000-8000-000000000000", !tun, tun)
			if _, err := serial.LoadJSONConfig(strings.NewReader(js)); err != nil {
				t.Fatalf("%s tun=%v: %v", n.Name, tun, err)
			}
		}
	}
}

// Ядро стартует в процессе (режим прокси): входы слушают, проверка доходит до узла
// (с ненастоящим UUID сервер не пустит — главное, что не «конфиг»/«порт занят»).
func TestLocalRunnerStarts(t *testing.T) {
	r := &localRunner{}
	if err := r.Run(buildXrayConfig(testNodes[0], "00000000-0000-4000-8000-000000000000", true, false)); err != nil {
		t.Fatalf("старт: %v", err)
	}
	defer r.Stop()
	res := probe(0, 6*time.Second)
	t.Logf("проверка с ненастоящим UUID: ok=%v %d мс %s", res.OK, res.Ms, res.Error)
	if strings.HasPrefix(res.Error, "socks: dial") {
		t.Fatalf("socks-вход не слушает: %s", res.Error)
	}
	up, down := r.Traffic()
	t.Logf("трафик ↑%d ↓%d, ядро %s", up, down, xrayVersion())
}

func TestSignature(t *testing.T) {
	if err := verifySignature(`{"v":1}`, "AAAA", pinnedPublicKey); err == nil {
		t.Fatal("подделка прошла проверку")
	}
	if err := verifySignature(`{"v":1}`, "AAAA", "x"); err == nil || !strings.Contains(err.Error(), "не совпадает") {
		t.Fatal("чужой ключ не отвергнут")
	}
}

func TestNewer(t *testing.T) {
	if !newer("0.1.20", "0.1.18") || newer("0.1.18", "0.1.18") || newer("0.1.9", "0.1.18") {
		t.Fatal("сравнение версий")
	}
}
