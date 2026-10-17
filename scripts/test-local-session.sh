#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
export PKG_CONFIG_PATH="$TASK_ROOT/.build/dependencies/libhangul/lib/pkgconfig"
swift build
TASK_PRODUCTS="$(swift build --show-bin-path)"
TASK_QA="$TASK_ROOT/.build/local-session-qa"
mkdir -p "$TASK_QA"
clang -c Tests/NativeSession/NativeTextView.m -o "$TASK_QA/NativeTextView.o" -Wno-protocol
swiftc -parse-as-library -swift-version 5 \
    -I "$TASK_PRODUCTS" -I Sources/CLibHangul -I .build/dependencies/libhangul/include \
    -L "$TASK_PRODUCTS" -lHannyeongCore -L .build/dependencies/libhangul/lib -lhangul \
    -framework AppKit -framework InputMethodKit -framework Carbon \
    -import-objc-header Tests/NativeSession/NativeTextView.h \
    $(ls Sources/Hannyeong/*.swift | grep -v /Application.swift) Tests/NativeSession/LocalSessionQA.swift \
    "$TASK_QA/NativeTextView.o" -o "$TASK_QA/LocalSessionQA"
TASK_REPORT="${HANNYEONG_SESSION_REPORT_DIRECTORY:-$TASK_ROOT/.build/private-chat-improvement-2026-10-09/applied-surface-2026-10-10}"
TASK_RUNTIME="${HANNYEONG_LOCAL_RUNTIME:-$TASK_ROOT/.build/b3-runtime/runtime.json}"
mkdir -p "$TASK_REPORT"
chmod 700 "$TASK_REPORT"
"$TASK_QA/LocalSessionQA" "$TASK_RUNTIME" \
    "$TASK_REPORT/native-session.json" \
    "$TASK_ROOT/Tests/NativeSession/user-paragraph.json" \
    "$TASK_ROOT/Tests/NativeSession/user-fresh-paragraph.json"
