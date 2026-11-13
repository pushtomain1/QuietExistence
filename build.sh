#!/bin/zsh
# Builds QuietExistence.app. Set SIGN_ID to a real signing identity to keep
# macOS permissions across rebuilds (ad-hoc "-" signing resets them each build).
set -e
cd "$(dirname "$0")"
swift build -c release
APP="QuietExistence.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/QuietExistence "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
pkill -f "$APP/Contents/MacOS/QuietExistence" || true
# New ad-hoc signature = new app to macOS; clear stale permission entries
if [ "${SIGN_ID:--}" = "-" ]; then
  tccutil reset Accessibility com.quietexistence.app >/dev/null 2>&1 || true
  tccutil reset ScreenCapture com.quietexistence.app >/dev/null 2>&1 || true
fi
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
echo "Built $PWD/$APP"
