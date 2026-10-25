#!/bin/bash
# Compila PieMenu, la copia a /Applications (sustituyendo la versión anterior) y la abre.
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/build-app.sh
pkill -x PieMenu 2>/dev/null && sleep 0.5 || true
rm -rf /Applications/PieMenu.app
cp -R build/PieMenu.app /Applications/
open /Applications/PieMenu.app
echo "✓ /Applications/PieMenu.app"
