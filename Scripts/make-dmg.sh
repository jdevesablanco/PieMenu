#!/bin/bash
# build/PieMenu.app → build/PieMenu-<versión>.dmg (con acceso directo a Aplicaciones)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
[[ -d build/PieMenu.app ]] || Scripts/build-app.sh
STAGE="$(mktemp -d)"
cp -R build/PieMenu.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/LEEME - README.txt" <<'TXT'
PieMenu — arrastra PieMenu.app a Aplicaciones y ábrela con clic derecho → Abrir (solo la primera vez).
Si macOS dice que no puede verificar la app: Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente».
(La app no está notarizada por Apple; es software libre y el código está en GitHub.)

PieMenu — drag PieMenu.app to Applications and open it with right-click → Open (first time only).
If macOS says it can't verify the app: System Settings → Privacy & Security → "Open Anyway".
(The app isn't notarized by Apple; it's free software and the code is on GitHub.)
TXT
rm -f "build/PieMenu-$VERSION.dmg"
hdiutil create -volname "PieMenu" -srcfolder "$STAGE" -ov -format UDZO "build/PieMenu-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
echo "✓ build/PieMenu-$VERSION.dmg"
