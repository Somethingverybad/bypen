#!/bin/sh
# Установка Бупеня для текущего пользователя (без root): программа в ~/.local/bin,
# ярлык в меню приложений. Для режима TUN при подключении спросит пароль (pkexec).
set -eu
cd "$(dirname "$0")"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps"
install -m 755 bypen "$HOME/.local/bin/bypen"
install -m 644 bypen.png "$HOME/.local/share/icons/hicolor/256x256/apps/bypen.png"
sed "s|^Exec=bypen|Exec=$HOME/.local/bin/bypen|" bypen.desktop > "$HOME/.local/share/applications/bypen.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Бупень установлен: меню приложений → «Бупень» или команда ~/.local/bin/bypen"
