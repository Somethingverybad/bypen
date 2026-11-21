// Проверка связи через ядро: SOCKS5 на локальный вход Xray → HTTP «204». Только так видно,
// что путь до сервера живой (в режиме TUN собственные соединения ядра идут мимо туннеля).
package main

import (
	"bufio"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"
)

type probeResult struct {
	OK    bool
	Ms    int
	Error string
}

var probeTargets = []struct{ host, path string }{
	{"connectivitycheck.gstatic.com", "/generate_204"},
	{"cp.cloudflare.com", "/"},
	{"www.google.com", "/generate_204"},
}

func probe(attempt int, timeout time.Duration) probeResult {
	t := probeTargets[attempt%len(probeTargets)]
	t0 := time.Now()
	fail := func(f string, a ...any) probeResult {
		return probeResult{Ms: int(time.Since(t0).Milliseconds()), Error: fmt.Sprintf(f, a...)}
	}
	c, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(socksPort), 3*time.Second)
	if err != nil {
		return fail("socks: %v", err)
	}
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(timeout))
	buf := make([]byte, 262)
	if _, err := c.Write([]byte{5, 1, 0}); err != nil {
		return fail("socks: %v", err)
	}
	if _, err := readFull(c, buf[:2]); err != nil || buf[1] != 0 {
		return fail("socks: метод отвергнут")
	}
	req := []byte{5, 1, 0, 3, byte(len(t.host))}
	req = append(req, t.host...)
	req = append(req, 0, 80)
	if _, err := c.Write(req); err != nil {
		return fail("socks: %v", err)
	}
	if _, err := readFull(c, buf[:4]); err != nil {
		return timeoutOr(err, t.host, timeout, fail)
	}
	if buf[1] != 0 {
		return fail("socks: отказ %d", buf[1])
	}
	switch buf[3] {
	case 1:
		_, err = readFull(c, buf[:6])
	case 4:
		_, err = readFull(c, buf[:18])
	default:
		if _, err = readFull(c, buf[:1]); err == nil {
			_, err = readFull(c, buf[:int(buf[0])+2])
		}
	}
	if err != nil {
		return timeoutOr(err, t.host, timeout, fail)
	}
	fmt.Fprintf(c, "GET %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n", t.path, t.host)
	line, err := bufio.NewReader(c).ReadString('\n')
	if err != nil {
		if line == "" {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				return fail("таймаут %d с (%s)", int(timeout.Seconds()), t.host)
			}
			return fail("http: соединение закрыто без ответа")
		}
	}
	f := strings.Fields(line)
	if len(f) >= 2 && strings.HasPrefix(f[0], "HTTP/1.") {
		if code, err := strconv.Atoi(f[1]); err == nil && code < 500 {
			return probeResult{OK: true, Ms: int(time.Since(t0).Milliseconds())}
		}
	}
	return fail("http: %.40s", strings.TrimSpace(line))
}

func timeoutOr(err error, host string, timeout time.Duration, fail func(string, ...any) probeResult) probeResult {
	if ne, ok := err.(net.Error); ok && ne.Timeout() {
		return fail("таймаут %d с (%s)", int(timeout.Seconds()), host)
	}
	return fail("socks: соединение закрыто")
}

func readFull(c net.Conn, b []byte) (int, error) {
	n := 0
	for n < len(b) {
		m, err := c.Read(b[n:])
		n += m
		if err != nil {
			return n, err
		}
	}
	return n, nil
}
