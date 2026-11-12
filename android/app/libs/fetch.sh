#!/bin/sh
# Готовые сборки ядра для Android (в git не кладём, ~55 МБ):
#   libXray.aar          — Xray-core (gomobile), github.com/XTLS/libXray
#   hev-socks5-tunnel.aar — tun → socks5, github.com/heiher/hev-socks5-tunnel (minSdk 29)
set -e
cd "$(dirname "$0")"
get() { # имя url sha256 [путь_внутри_zip]
  [ -f "$1" ] && echo "$1 на месте" && return
  curl -L -o "$1.dl" "$2"; echo "$3  $1.dl" | shasum -a 256 -c -
  if [ -n "$4" ]; then unzip -q -o "$1.dl" -d tmp && mv "tmp/$4" "$1" && rm -rf tmp "$1.dl"; else mv "$1.dl" "$1"; fi
  echo "$1 готов"
}
get libXray.aar https://github.com/XTLS/libXray/releases/download/v26.11.9/libxray-android.zip \
  1b1aa12124a7112af983a6cea74c77f27aadc6b650acf3c5a57019619ba9fa48 libxray-android/libXray.aar
get hev-socks5-tunnel.aar https://github.com/heiher/hev-socks5-tunnel/releases/download/2.19.3/hev-socks5-tunnel.aar \
  ab6c581e6157680cfe5687ee7bbdcf95405c006c2db3701879ec44b9e5f83836
