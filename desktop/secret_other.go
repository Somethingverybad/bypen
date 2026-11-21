//go:build !windows

package main

// На Linux файл и так только для владельца (0600) в ~/.config/bypen.
func protect(b []byte) ([]byte, error)   { return b, nil }
func unprotect(b []byte) ([]byte, error) { return nil, errNotProtected }
