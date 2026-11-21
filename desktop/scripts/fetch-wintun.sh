#!/bin/sh
# wintun.dll (драйвер TUN для Windows, wintun.net) — вшивается в bypen.exe. Сумма архива закреплена.
set -eu
cd "$(dirname "$0")/.."
[ -f third_party/wintun/wintun.dll ] && exit 0
T=$(mktemp -d)
curl -sfL -o "$T/w.zip" https://www.wintun.net/builds/wintun-0.14.1.zip
echo "07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51  $T/w.zip" | shasum -a 256 -c -
unzip -q "$T/w.zip" -d "$T"
mkdir -p third_party/wintun
cp "$T/wintun/bin/amd64/wintun.dll" "$T/wintun/LICENSE.txt" third_party/wintun/
rm -rf "$T"
