//go:build windows

package main

import (
	"unsafe"

	"golang.org/x/sys/windows"
)

// DPAPI: расшифровать может только этот пользователь Windows.
func protect(b []byte) ([]byte, error) {
	if len(b) == 0 {
		return b, nil
	}
	in := windows.DataBlob{Size: uint32(len(b)), Data: &b[0]}
	var out windows.DataBlob
	if err := windows.CryptProtectData(&in, nil, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &out); err != nil {
		return nil, err
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(out.Data)))
	res := make([]byte, out.Size)
	copy(res, unsafe.Slice(out.Data, out.Size))
	return append([]byte("DPAPI1"), res...), nil
}

func unprotect(b []byte) ([]byte, error) {
	if len(b) < 6 || string(b[:6]) != "DPAPI1" {
		return nil, errNotProtected
	}
	b = b[6:]
	if len(b) == 0 {
		return b, nil
	}
	in := windows.DataBlob{Size: uint32(len(b)), Data: &b[0]}
	var out windows.DataBlob
	if err := windows.CryptUnprotectData(&in, nil, nil, 0, nil, windows.CRYPTPROTECT_UI_FORBIDDEN, &out); err != nil {
		return nil, err
	}
	defer windows.LocalFree(windows.Handle(unsafe.Pointer(out.Data)))
	res := make([]byte, out.Size)
	copy(res, unsafe.Slice(out.Data, out.Size))
	return res, nil
}
