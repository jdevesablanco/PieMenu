# Copia de referencia del cask publicado en jdevesablanco/homebrew-tap (Casks/piemenu.rb).
cask "piemenu" do
  version "1.0.1"
  sha256 "b26ac5b91c124876e80522ddaceecc5eefc78538d5a05e1a902e12b482469996"

  url "https://github.com/jdevesablanco/PieMenu/releases/download/v#{version}/PieMenu-#{version}.dmg"
  name "PieMenu"
  desc "Radial menu at the pointer for your apps, shortcuts and Automator workflows"
  homepage "https://github.com/jdevesablanco/PieMenu"

  depends_on macos: :ventura

  app "PieMenu.app"

  # La app no está notarizada (no hay cuenta de Apple Developer de pago): sin esto macOS la bloquearía al abrirla.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/PieMenu.app"], must_succeed: false
  end

  uninstall quit: "com.jdevesablanco.piemenu"
  zap trash: "~/Library/Application Support/PieMenu"
end
