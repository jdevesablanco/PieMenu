#!/bin/bash
# build/PieMenu.app → build/PieMenu-<versión>.pkg (instala en /Applications y la abre)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
[[ -d build/PieMenu.app ]] || Scripts/build-app.sh
W="$(mktemp -d)"
mkdir -p "$W/root" "$W/scripts"
cp -R build/PieMenu.app "$W/root/"
cat > "$W/scripts/postinstall" <<'SH'
#!/bin/bash
# Abre la app como el usuario con la sesión iniciada (el instalador corre como root).
U="$(stat -f%Su /dev/console)"
[ -n "$U" ] && [ "$U" != "root" ] && sudo -u "$U" open -a /Applications/PieMenu.app || true
exit 0
SH
chmod +x "$W/scripts/postinstall"
# Sin esto, si ya hay una copia de la app en otra carpeta, Installer la «reubica» allí en vez de en /Applications.
pkgbuild --analyze --root "$W/root" "$W/component.plist" >/dev/null
# (en macOS recientes --analyze ya no escribe la clave: se borra si está y se añade)
/usr/libexec/PlistBuddy -c "Delete :0:BundleIsRelocatable" "$W/component.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$W/component.plist"
pkgbuild --root "$W/root" --component-plist "$W/component.plist" --scripts "$W/scripts" --identifier com.jdevesablanco.piemenu.pkg \
  --version "$VERSION" --install-location /Applications "$W/PieMenu-component.pkg" >/dev/null
cat > "$W/dist.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <title>PieMenu</title>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <choices-outline><line choice="default"><line choice="app"/></line></choices-outline>
  <choice id="default"/>
  <choice id="app" visible="false"><pkg-ref id="com.jdevesablanco.piemenu.pkg"/></choice>
  <pkg-ref id="com.jdevesablanco.piemenu.pkg" version="$VERSION" onConclusion="none">PieMenu-component.pkg</pkg-ref>
</installer-gui-script>
XML
rm -f "build/PieMenu-$VERSION.pkg"
productbuild --distribution "$W/dist.xml" --package-path "$W" "build/PieMenu-$VERSION.pkg" >/dev/null
rm -rf "$W"
echo "✓ build/PieMenu-$VERSION.pkg"
