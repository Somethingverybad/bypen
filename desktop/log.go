// Журнал как на iPhone/маке: «dd.MM HH:mm:ss [win] сообщение», файл ограничен по размеру.
package main

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
)

type tunnelLog struct {
	mu  sync.Mutex
	tag string
}

var tlog = &tunnelLog{tag: platformShort()}

func platformShort() string {
	switch platformTag() {
	case "windows":
		return "win"
	case "linux":
		return "linux"
	}
	return platformTag()
}

func (l *tunnelLog) Log(format string, a ...any) {
	line := fmt.Sprintf("%s [%s] %s\n", time.Now().Format("02.01 15:04:05"), l.tag, fmt.Sprintf(format, a...))
	l.mu.Lock()
	defer l.mu.Unlock()
	p := logPath()
	if st, err := os.Stat(p); err == nil && st.Size() > 512*1024 {
		if b, err := os.ReadFile(p); err == nil {
			_ = os.WriteFile(p, b[len(b)/2:], 0o600)
		}
	}
	f, err := os.OpenFile(p, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.WriteString(line)
	if os.Getenv("BYPEN_STDERR") != "" {
		fmt.Fprint(os.Stderr, line)
	}
}

func (l *tunnelLog) Read() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	b, _ := os.ReadFile(logPath())
	return tail(string(b), 60000)
}

func (l *tunnelLog) Clear() {
	l.mu.Lock()
	defer l.mu.Unlock()
	_ = os.WriteFile(logPath(), nil, 0o600)
	_ = os.WriteFile(xrayLogPath(), nil, 0o600)
}

func tail(s string, n int) string {
	if len(s) <= n {
		return s
	}
	s = s[len(s)-n:]
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = s[i+1:]
	}
	return s
}
