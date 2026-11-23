#!/bin/zsh
# Сборка Бупеня для Windows и Linux (x64) с мака: Go без cgo собирает родные x64-программы.
#   scripts/build.sh            → dist/bypen-windows-x64.zip, dist/bypen-linux-x64.tar.gz
set -eu
cd "$(dirname "$0")/.."
scripts/fetch-wintun.sh
if [[ ! -f rsrc_windows_amd64.syso || assets/icon.ico -nt rsrc_windows_amd64.syso ]]; then sh scripts/resources.sh; fi
N=$(git rev-list --count HEAD)
V="${BYPEN_VERSION:-0.1.$N}"
LD="-s -w -X main.version=$V"
mkdir -p dist
rm -rf dist/win dist/linux
mkdir -p dist/win dist/linux
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "$LD -H windowsgui" -o dist/win/bypen.exe .
cp third_party/wintun/wintun.dll dist/win/
cp third_party/wintun/LICENSE.txt dist/win/wintun-LICENSE.txt
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "$LD" -o dist/linux/bypen .
cp packaging/linux/bypen.desktop packaging/linux/install.sh dist/linux/
cp ui/icon.png dist/linux/bypen.png
(cd dist/win && zip -q -9 ../bypen-windows-x64.zip bypen.exe wintun.dll wintun-LICENSE.txt)
(cd dist && mv linux bypen && COPYFILE_DISABLE=1 tar --no-xattrs -czf bypen-linux-x64.tar.gz bypen && mv bypen linux)
cd dist && shasum -a 256 bypen-windows-x64.zip bypen-linux-x64.tar.gz > SHA256SUMS && ls -la *.zip *.tar.gz && echo "версия $V"
