#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
export PKG_CONFIG_PATH="$task_root/.build/dependencies/libhangul/lib/pkgconfig"
exec swift run jev-ime-eval "$@"
