// Профиль «Сети WYX» — GET /api/vpn/profile/ (backend/chat/vpn.py). payload — строка JSON,
// подписанная Ed25519; ключ сервера зашит сюда, подменить список узлов по дороге нельзя.
package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/netip"
	"os"
	"strings"
)

const (
	pinnedPublicKey = "mom4ETYn/8XuqZxbKEWEgk9DJcGK+l31/i4e9Bwc4Bw="
	updateBase      = "https://storage.yandexcloud.net/hyax-public/installers/bypen/"
)

// Переменная, а не константа: тесты подставляют свой сервер.
var apiBase = "https://hyax.ru/api"

type VpnNode struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Kind      string   `json:"kind"` // reality | xhttp
	Host      string   `json:"host"`
	Port      int      `json:"port"`
	SNI       string   `json:"sni"`
	IPs       []string `json:"ips"`
	Weight    int      `json:"weight"`
	OK        bool     `json:"ok"`
	RttMs     *int     `json:"rtt_ms"`
	CheckedAt *string  `json:"checked_at"`
	Pbk       string   `json:"pbk"`
	Sid       string   `json:"sid"`
	Fp        string   `json:"fp"`
	Flow      string   `json:"flow"`
	Path      string   `json:"path"`
	Mode      string   `json:"mode"`
	ALPN      []string `json:"alpn"`
}

func (n VpnNode) IsReality() bool { return n.Kind == "reality" }

// DialAddress — IP, который пробник видит из Москвы, иначе имя.
func (n VpnNode) DialAddress() string {
	for _, ip := range n.IPs {
		if _, err := netip.ParseAddr(ip); err == nil {
			return ip
		}
	}
	return n.Host
}

type VpnUser struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	UUID     string `json:"uuid"`
	Email    string `json:"email"`
}

// DirectList — куда ходить напрямую, мимо узла: сам WYX и его хранилища (они в России).
// Приходит в подписанном профиле; встроенный список — на случай старого сервера.
type DirectList struct {
	Domains []string `json:"domains"`
	CIDRs   []string `json:"cidrs"`
}

var builtinDirect = DirectList{
	Domains: []string{"hyax.ru", "wyx.su", "huyax.e-tree.su", "storage.yandexcloud.net",
		"43fb9b03-c74c-45ab-b258-7872345451b3.selcdn.net"},
	CIDRs: []string{"194.164.245.144/32"},
}

// Исключения системного прокси: суффикс → сам домен и wild+домен (wild — «*.» или «.» у KDE),
// «full:домен» → только он.
func (d DirectList) bypassHosts(wild string) []string {
	var out []string
	for _, x := range d.Domains {
		if strings.HasPrefix(x, "full:") {
			out = append(out, strings.TrimPrefix(x, "full:"))
		} else {
			out = append(out, x, wild+x)
		}
	}
	return out
}

func (d DirectList) merged(o *DirectList) DirectList {
	if o == nil {
		return d
	}
	seen := map[string]bool{}
	uniq := func(a []string) []string {
		var out []string
		for _, x := range a {
			k := strings.ToLower(strings.TrimSpace(x))
			if k == "" || seen[k] {
				continue
			}
			seen[k] = true
			out = append(out, k)
		}
		return out
	}
	doms := uniq(append(append([]string{}, d.Domains...), o.Domains...))
	seen = map[string]bool{}
	var cidrs []string
	for _, c := range uniq(append(append([]string{}, d.CIDRs...), o.CIDRs...)) {
		if _, err := netip.ParsePrefix(c); err == nil {
			cidrs = append(cidrs, c)
		}
	}
	return DirectList{Domains: doms, CIDRs: cidrs}
}

type VpnProfile struct {
	V        int         `json:"v"`
	IssuedAt string      `json:"issued_at"`
	TTL      int         `json:"ttl"`
	User     VpnUser     `json:"user"`
	Nodes    []VpnNode   `json:"nodes"`
	Direct   *DirectList `json:"direct"`
}

// directList — встроенный список + с сервера.
func (p *VpnProfile) directList() DirectList {
	if p == nil {
		return builtinDirect
	}
	return builtinDirect.merged(p.Direct)
}

func decodeProfile(payload string) (*VpnProfile, error) {
	var p VpnProfile
	if err := json.Unmarshal([]byte(payload), &p); err != nil {
		return nil, err
	}
	return &p, nil
}

func loadSavedProfile() *VpnProfile {
	b, err := os.ReadFile(profilePath())
	if err != nil {
		return nil
	}
	p, err := decodeProfile(string(b))
	if err != nil {
		return nil
	}
	return p
}

// order — выбранный вручную первым, дальше как отдал сервер (живые первыми).
func (p *VpnProfile) order(preferred *string) []VpnNode {
	list := append([]VpnNode(nil), p.Nodes...)
	if preferred == nil {
		return list
	}
	for i, n := range list {
		if n.ID == *preferred {
			out := []VpnNode{n}
			out = append(out, list[:i]...)
			return append(out, list[i+1:]...)
		}
	}
	return list
}

func (p *VpnProfile) node(id string) *VpnNode {
	for i := range p.Nodes {
		if p.Nodes[i].ID == id {
			return &p.Nodes[i]
		}
	}
	return nil
}

func verifySignature(payload, sig, pub string) error {
	if pub != pinnedPublicKey {
		return errors.New("ключ подписи не совпадает с зашитым в приложение")
	}
	if sig == "" {
		return errors.New("ответ сервера без подписи")
	}
	k, err1 := base64.StdEncoding.DecodeString(pinnedPublicKey)
	s, err2 := base64.StdEncoding.DecodeString(sig)
	if err1 != nil || err2 != nil || len(k) != ed25519.PublicKeySize {
		return errors.New("ключ подписи не разобран")
	}
	if !ed25519.Verify(ed25519.PublicKey(k), []byte(payload), s) {
		return errors.New("подпись профиля не сходится")
	}
	return nil
}
