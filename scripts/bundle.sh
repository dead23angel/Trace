#!/bin/bash
# Builds Trace and assembles build/Trace.app.
#
#   scripts/bundle.sh            release build, ad-hoc signed
#   scripts/bundle.sh debug      debug build
#
# Set CODESIGN_IDENTITY to a certificate name (see `security find-identity -v
# -p codesigning`) to sign with it. With the default ad-hoc signature macOS
# treats every rebuild as a new app, so Accessibility access has to be granted
# again after each build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
# A local, untracked .codesign-identity file saves typing the variable each time.
if [ -z "${CODESIGN_IDENTITY:-}" ] && [ -f .codesign-identity ]; then
  CODESIGN_IDENTITY="$(head -n 1 .codesign-identity)"
fi
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/Trace.app"

# UNIVERSAL=1 builds for both Apple silicon and Intel.
ARCHS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Trace"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Trace"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# English is the source language; an empty en.lproj lets macOS list it.
mkdir -p "$APP/Contents/Resources/en.lproj"

# The hardened runtime is required for notarization and harmless otherwise.
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
echo "Built $APP"
