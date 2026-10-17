#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MODE="${1:-run}"
TASK_APP="$TASK_ROOT/dist/TypingLab.app"
cd "$TASK_ROOT"
if pgrep -x TypingLab >/dev/null; then pkill -x TypingLab; fi
swift build -c release --product TypingLab
TASK_BINARY="$(swift build -c release --show-bin-path)/TypingLab"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BINARY" "$TASK_APP/Contents/MacOS/TypingLab"
cp "$TASK_ROOT/Resources/default-sentences.txt" "$TASK_APP/Contents/Resources/default-sentences.txt"
cat > "$TASK_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TypingLab</string>
<key>CFBundleIdentifier</key><string>com.yeop.TypingLab</string>
<key>CFBundleName</key><string>TypingLab</string>
<key>CFBundleDisplayName</key><string>TypingLab</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign "Developer ID Application: Sang Yeop Lim (79Q5RV23F9)" --options runtime --timestamp "$TASK_APP"
codesign --verify --strict "$TASK_APP"
case "$TASK_MODE" in
    --build) ;;
    --smoke) open -n "$TASK_APP" --args --smoke "$TASK_ROOT/smoke-result.json" ;;
    run|--verify) open -n "$TASK_APP" ;;
    *) echo "usage: $0 [run|--build|--smoke|--verify]" >&2;exit 2 ;;
esac
if [[ "$TASK_MODE" == "--verify" ]]; then sleep 1;pgrep -x TypingLab;fi
