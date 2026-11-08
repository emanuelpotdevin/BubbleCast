#!/bin/zsh
# Builds BubbleCast.app next to this script.
#   ./build.sh               build for this Mac
#   UNIVERSAL=1 ./build.sh   build one app for Apple silicon + Intel (used for GitHub releases)
set -e
cd "$(dirname "$0")"
APP=build/BubbleCast.app
BIN="$APP/Contents/MacOS/BubbleCast"
rm -rf "$APP" build/AppIcon.iconset build/arch
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
if [[ -n "$UNIVERSAL" ]]; then
  mkdir -p build/arch
  for ARCH in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$ARCH-apple-macos15.0" Sources/*.swift -o "build/arch/$ARCH"
  done
  lipo -create build/arch/arm64 build/arch/x86_64 -output "$BIN"
else
  swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos15.0" Sources/*.swift -o "$BIN"
fi
cp Info.plist "$APP/Contents/Info.plist"
swift make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# A stable signing identity keeps macOS permissions across rebuilds; fall back to ad-hoc.
IDENTITY=$(security find-identity -p codesigning -v | grep -m1 "Apple Development" | awk '{print $2}')
codesign --force --options runtime --entitlements entitlements.plist --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
