// Конфигурация Xray для одного узла: socks (+http для системного прокси) и, в режиме TUN,
// встроенный вход tun ядра: свои маршруты 0/1 + 128/1 (и IPv6), собственные соединения
// ядра привязаны к физическому интерфейсу (autoOutboundsInterface), на Windows WFP не даёт
// DNS утечь мимо туннеля. Частные сети — напрямую. Счётчики трафика — через stats.
package main

import (
	"encoding/json"
	"os"
	"runtime"
	"strconv"
)

// Порты локальных входов. BYPEN_PORT_BASE — только для проверок (не мешать другому клиенту).
var socksPort, httpPort = portsFromEnv()

func portsFromEnv() (int, int) {
	if v := os.Getenv("BYPEN_PORT_BASE"); v != "" {
		if b, err := strconv.Atoi(v); err == nil && b > 1024 && b < 65000 {
			return b, b + 1
		}
	}
	return 10808, 10809
}

var privateNets = []string{
	"10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.0/8", "169.254.0.0/16",
	"100.64.0.0/10", "224.0.0.0/4", "fc00::/7", "fe80::/10", "ff00::/8",
}

var tunDNS = []string{"1.1.1.1", "8.8.8.8"}

func tunName() string {
	if runtime.GOOS == "windows" {
		return "Bypen"
	}
	return "bypen0"
}

func buildXrayConfig(n VpnNode, uuid string, withHTTP, tun bool, direct DirectList) string {
	user := map[string]any{"id": uuid, "encryption": "none"}
	if n.Flow != "" {
		user["flow"] = n.Flow
	}
	fp := n.Fp
	if fp == "" {
		fp = "chrome"
	}
	var stream map[string]any
	if n.IsReality() {
		stream = map[string]any{
			"network":  "tcp",
			"security": "reality",
			"realitySettings": map[string]any{
				"serverName": n.SNI, "fingerprint": fp, "publicKey": n.Pbk, "shortId": n.Sid, "spiderX": "/",
			},
		}
	} else {
		alpn := n.ALPN
		if len(alpn) == 0 {
			alpn = []string{"h2"}
		}
		path, mode := n.Path, n.Mode
		if path == "" {
			path = "/"
		}
		if mode == "" {
			mode = "auto"
		}
		stream = map[string]any{
			"network":       "xhttp",
			"security":      "tls",
			"tlsSettings":   map[string]any{"serverName": n.SNI, "alpn": alpn, "fingerprint": fp},
			"xhttpSettings": map[string]any{"host": n.Host, "path": path, "mode": mode},
		}
	}
	stream["sockopt"] = map[string]any{"tcpKeepAliveInterval": 30}

	sniff := map[string]any{"enabled": true, "destOverride": []string{"http", "tls", "quic"}, "routeOnly": false}
	inbounds := []any{map[string]any{
		"tag": "socks", "listen": "127.0.0.1", "port": socksPort, "protocol": "socks",
		"settings": map[string]any{"auth": "noauth", "udp": true}, "sniffing": sniff,
	}}
	if withHTTP {
		inbounds = append(inbounds, map[string]any{"tag": "http", "listen": "127.0.0.1", "port": httpPort, "protocol": "http", "sniffing": sniff})
	}
	if tun {
		ts := map[string]any{
			"name":                   tunName(),
			"mtu":                    1500,
			"gateway":                []string{"198.18.0.1/24", "fd00:7779:7878::1/64"},
			"autoSystemRoutingTable": []string{"0.0.0.0/1", "128.0.0.0/1", "::/1", "8000::/1"},
			"autoOutboundsInterface": "auto",
		}
		if runtime.GOOS == "windows" {
			ts["dns"] = tunDNS
			ts["autoSystemWfpBlockLeak"] = []string{"dns", "misconfigtun"}
		}
		inbounds = append(inbounds, map[string]any{"tag": "tun", "protocol": "tun", "settings": ts, "sniffing": sniff})
	}
	cfg := map[string]any{
		"log":      map[string]any{"loglevel": "warning", "error": xrayLogPath()},
		"stats":    map[string]any{},
		"policy":   map[string]any{"system": map[string]any{"statsOutboundUplink": true, "statsOutboundDownlink": true}},
		"inbounds": inbounds,
		"outbounds": []any{
			map[string]any{
				"tag": "proxy", "protocol": "vless",
				"settings": map[string]any{"vnext": []any{map[string]any{
					"address": n.DialAddress(), "port": n.Port, "users": []any{user},
				}}},
				"streamSettings": stream,
			},
			map[string]any{"tag": "direct", "protocol": "freedom"},
			map[string]any{"tag": "block", "protocol": "blackhole"},
		},
		"routing": map[string]any{
			"domainStrategy": "AsIs",
			"rules": append(directRules(direct),
				map[string]any{"type": "field", "ip": privateNets, "outboundTag": "direct"},
				map[string]any{"type": "field", "network": "tcp,udp", "outboundTag": "proxy"},
			),
		},
	}
	b, _ := json.Marshal(cfg)
	return string(b)
}

// WYX — напрямую: по имени (SNI/Host, ядро подсматривает) и по адресам. В режиме TUN прямые
// соединения ядра привязаны к физическому интерфейсу (autoOutboundsInterface) — в туннель не вернутся.
func directRules(d DirectList) []any {
	var rules []any
	if len(d.Domains) > 0 {
		doms := make([]string, len(d.Domains))
		for i, x := range d.Domains {
			doms[i] = "domain:" + x
		}
		rules = append(rules, map[string]any{"type": "field", "domain": doms, "outboundTag": "direct"})
	}
	if len(d.CIDRs) > 0 {
		rules = append(rules, map[string]any{"type": "field", "ip": d.CIDRs, "outboundTag": "direct"})
	}
	return rules
}
