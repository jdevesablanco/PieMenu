#!/bin/bash
# Compila PieMenu y monta build/PieMenu.app.
#   Scripts/build-app.sh                 → firma ad-hoc (gratis, funciona en tu Mac)
#   SIGN_ID="Developer ID Application: …" Scripts/build-app.sh   → firma con tu certificado (para notarizar)
#   UNIVERSAL=1 Scripts/build-app.sh     → binario arm64 + x86_64 (necesita Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:-com.jdevesablanco.piemenu}"
VERSION="${VERSION:-1.0.0}"
SIGN_ID="${SIGN_ID:--}"
OUT="${OUT:-build}"
APP="$OUT/PieMenu.app"

ARCHS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

[[ -f Resources/AppIcon.icns ]] || swift Scripts/make-icon.swift Resources/AppIcon.icns
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PieMenu" "$APP/Contents/MacOS/PieMenu"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/@BUNDLE_ID@/$BUNDLE_ID/g" -e "s/@VERSION@/$VERSION/g" Resources/Info.plist.template > "$APP/Contents/Info.plist"

OPTS=()
if [[ "$SIGN_ID" != "-" ]]; then OPTS=(--options runtime --timestamp); fi
codesign --force --sign "$SIGN_ID" ${OPTS[@]+"${OPTS[@]}"} "$APP"
codesign --verify --deep --strict "$APP" && echo "✓ firma verificada ($([[ "$SIGN_ID" == "-" ]] && echo ad-hoc || echo "$SIGN_ID"))"
echo "✓ $APP"
