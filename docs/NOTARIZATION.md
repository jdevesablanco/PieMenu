# Notarizar PieMenu (opcional, de pago)

PieMenu se distribuye firmada *ad-hoc* (gratis). Eso funciona perfectamente en el Mac que la compila y con `brew install`
(que compila en local), pero un `.dmg` descargado hace que Gatekeeper pida «Abrir igualmente» la primera vez.

Para quitar ese paso (y poder entrar en el repositorio oficial `homebrew/cask`, que desde septiembre de 2026 exige apps
firmadas y notarizadas) hace falta una cuenta de **Apple Developer Program (99 USD/año)**:

1. Crea un certificado «Developer ID Application» y expórtalo como `.p12`.
2. Crea una contraseña específica de app para notarizar (appleid.apple.com).
3. En local:
   ```bash
   SIGN_ID="Developer ID Application: Tu Nombre (TEAMID)" UNIVERSAL=1 Scripts/build-app.sh
   Scripts/make-dmg.sh
   xcrun notarytool submit build/PieMenu-1.0.0.dmg --apple-id TU_ID --team-id TEAMID --password APP_PASSWORD --wait
   xcrun stapler staple build/PieMenu-1.0.0.dmg
   ```
4. En GitHub Actions: guarda el `.p12` (base64), su contraseña y las credenciales de `notarytool` como *secrets* y añade los pasos
   anteriores al workflow (`import certificate` → `build-app.sh` con `SIGN_ID` → `notarytool` → `stapler`).

El script ya usa *hardened runtime* y *timestamp* cuando `SIGN_ID` no es `-`.
