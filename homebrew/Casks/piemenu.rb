# Copia de referencia del cask publicado en jdevesablanco/homebrew-tap (Casks/piemenu.rb).
cask "piemenu" do
  version "1.0.2"
  sha256 "5721d8d62169514bb2d062eed51b87e5bb364d084f02e9f380919d9b740e96c0"

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
