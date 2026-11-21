#!/bin/zsh
# Универсальная подписанная сборка Mac. Нотаризация и публикация — отдельные шаги.
# BYPEN_VERSION=0.1.18 BYPEN_BUILD=18 DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer sh scripts/build-mac.sh
set -eu
cd "$(dirname "$0")/.."
ROOT=$(cd .. && pwd)
N=${BYPEN_BUILD:-$(git rev-list --count HEAD)}
V=${BYPEN_VERSION:-0.1.$N}
DD=${BYPEN_DERIVED_DATA:-/tmp/bypen-mac-release-$N}
xcodegen generate
xcodebuild -project Bypen.xcodeproj -scheme BypenMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DD" \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_STYLE=Manual \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp \
  'CODE_SIGN_IDENTITY=Developer ID Application: Andrey Cherenev (BTQ69VVHX6)' \
  CURRENT_PROJECT_VERSION="$N" MARKETING_VERSION="$V" build
# Xcode при встраивании tool может сохранить прежние отладочные entitlements.
# Подписываем изнутри наружу с явными правами и timestamp перед упаковкой.
APP="$DD/Build/Products/Release/Bypen.app"
IDENTITY="Developer ID Application: Andrey Cherenev (BTQ69VVHX6)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements Mac/Helper/Release.entitlements "$APP/Contents/MacOS/bypen-tun"
codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements Mac/BypenMac.entitlements "$APP"
codesign --verify --deep --strict "$DD/Build/Products/Release/Bypen.app"
mkdir -p "$ROOT/desktop/dist/mac"
ditto --rsrc --extattr "$DD/Build/Products/Release/Bypen.app" "$ROOT/desktop/dist/mac/Bypen.app"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/desktop/dist/mac/Bypen.app" "$ROOT/desktop/dist/bypen-mac-$V.zip"
