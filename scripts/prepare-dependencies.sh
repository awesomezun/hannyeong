#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_commit=5094421d9586294b2aad09924b9a54e2e6060f06
task_source="$task_root/.build/dependencies/libhangul-source"
task_build="$task_root/.build/dependencies/libhangul-build"
task_prefix="$task_root/.build/dependencies/libhangul"
mkdir -p "$task_root/.build/dependencies"
if [ ! -d "$task_source/.git" ]; then
    git clone https://github.com/libhangul/libhangul.git "$task_source"
fi
git -C "$task_source" checkout --detach "$task_commit"
cmake -S "$task_source" -B "$task_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_INSTALL_PREFIX="$task_prefix" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DENABLE_TOOLS=OFF \
    -DENABLE_EXTERNAL_KEYBOARDS=OFF
cmake --build "$task_build" --parallel
cmake --install "$task_build"
