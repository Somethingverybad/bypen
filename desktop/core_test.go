package main

import (
	"net/http"
	"net/url"
	"strconv"
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
			js := buildXrayConfig(n, "00000000-0000-4000-8000-000000000000", !tun, tun, builtinDirect.merged(&DirectList{CIDRs: []string{"203.0.113.0/24", "bad"}}))
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
	if err := r.Run(buildXrayConfig(testNodes[0], "00000000-0000-4000-8000-000000000000", true, false, builtinDirect)); err != nil {
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

func TestDirectMerge(t *testing.T) {
	d := builtinDirect.merged(&DirectList{Domains: []string{"HYAX.ru", "new.example"}, CIDRs: []string{"194.164.245.144/32", "2a02:6b8::1d9/128", "мусор"}})
	if len(d.Domains) != len(builtinDirect.Domains)+1 {
		t.Fatalf("домены: %v", d.Domains)
	}
	if len(d.CIDRs) != 2 {
		t.Fatalf("адреса: %v", d.CIDRs)
	}
}

// WYX идёт мимо узла: ключ узла ненастоящий, через него ничего не пройдёт, а hyax.ru отвечает —
// значит, ушло напрямую. Чужой сайт при этом не открывается (идёт в узел).
func TestDirectBypassesNode(t *testing.T) {
	r := &localRunner{}
	if err := r.Run(buildXrayConfig(testNodes[0], "00000000-0000-4000-8000-000000000000", true, false, builtinDirect)); err != nil {
		t.Fatalf("старт: %v", err)
	}
	defer r.Stop()
	pu, _ := url.Parse("socks5://127.0.0.1:" + strconv.Itoa(socksPort))
	c := &http.Client{Timeout: 12 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(pu)}}
	for _, u := range []string{"https://hyax.ru/api/vpn/profile/", "https://storage.yandexcloud.net/hyax-public/installers/bypen/android.json"} {
		resp, err := c.Get(u)
		if err != nil {
			t.Fatalf("%s напрямую не открылся: %v", u, err)
		}
		resp.Body.Close()
		t.Logf("%s → %d (напрямую)", u, resp.StatusCode)
	}
	if resp, err := c.Get("https://example.com/"); err == nil {
		resp.Body.Close()
		t.Fatalf("чужой сайт открылся мимо узла (%d)", resp.StatusCode)
	} else {
		t.Logf("example.com через узел с ненастоящим ключом: ошибка, как и должно быть")
	}
}
