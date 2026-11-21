#!/bin/sh
# Иконка EXE/окна. После изменения assets/icon.ico обновить и добавить .syso в Git.
set -eu
cd "$(dirname "$0")/.."
go run github.com/akavel/rsrc@v0.10.2 -ico assets/icon.ico -arch amd64 -o rsrc_windows_amd64.syso
