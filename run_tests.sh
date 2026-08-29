#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
XDG_ROOT="${TMPDIR:-/tmp}/keyflow-xdg"

mkdir -p "$XDG_ROOT/config" "$XDG_ROOT/data" "$XDG_ROOT/state" "$XDG_ROOT/cache"

XDG_CONFIG_HOME="$XDG_ROOT/config" \
XDG_DATA_HOME="$XDG_ROOT/data" \
XDG_STATE_HOME="$XDG_ROOT/state" \
XDG_CACHE_HOME="$XDG_ROOT/cache" \
nvim --clean --headless -u NONE -c "set rtp^=$ROOT" -c "luafile $ROOT/test/keyflow_spec.lua" -c "qa!"
