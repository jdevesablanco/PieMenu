// PackCatalog.swift — catálogo, detección e instalación de las apps de la familia, y sus tarjetas.
//
// Este archivo es IDÉNTICO en todas las apps de la familia: si cambias algo, cópialo a todas.
// No depende de nada de cada app (solo SwiftUI/AppKit). Cada app puede ajustar, al arrancar:
//   PackCatalog.isSpanish = { … }     // idioma elegido en la app (por defecto, el del sistema)
//   PackCatalog.accent = …            // color de acento (por defecto, el morado de la familia)

import SwiftUI
import AppKit

struct PackApp: Identifiable, Equatable {
    let id: String          // bundle ID
    let name: String        // nombre del .app y del repo en GitHub
    let cask: String        // jdevesablanco/tap/<cask>
    let symbol: String      // SF Symbol mientras no esté instalada
    let es: String
    let en: String
    let released: Bool      // false = «Próximamente»
}

enum PackCatalog {
    static var isSpanish: () -> Bool = { (Locale.preferredLanguages.first ?? "en").hasPrefix("es") }
    static var accent = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let owner = "jdevesablanco"

    static let apps: [PackApp] = [
        PackApp(id: "io.github.jdevesablanco.SplitExercises", name: "SplitExercises", cask: "splitexercises", symbol: "rectangle.split.1x2",
                es: "Divide PDFs de ejercicios en una hoja por ejercicio, con clic derecho.",
                en: "Splits exercise PDFs into one sheet per exercise, from the right-click menu.", released: true),
        PackApp(id: "com.jdevesablanco.quitall", name: "QuitAll", cask: "quitall", symbol: "power",
                es: "Cierra todas las apps de un clic, menos las que elijas.",
                en: "Quits every app in one click, except the ones you pick.", released: true),
        PackApp(id: "com.jdevesablanco.piemenu", name: "PieMenu", cask: "piemenu", symbol: "circle.circle",
                es: "Un menú circular junto al puntero con tus apps, atajos y Automator, con ⌃Tab.",
                en: "A radial menu at the pointer with your apps, shortcuts and Automator, on ⌃Tab.", released: true),
    ]

    static func t(_ es: String, _ en: String) -> String { isSpanish() ? es : en }

    static var current: PackApp? { apps.first { $0.id == Bundle.main.bundleIdentifier } }

    // MARK: detección

    static func installedURL(_ app: PackApp) -> URL? {
        if app.id == Bundle.main.bundleIdentifier { return Bundle.main.bundleURL }
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id) { return u }
        let fm = FileManager.default
        for dir in ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
            let p = "\(dir)/\(app.name).app"
            if fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    static var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func open(_ app: PackApp) {
        guard let u = installedURL(app) else { return }
        NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
    }

    static func releasesPage(_ app: PackApp) -> URL { URL(string: "https://github.com/\(owner)/\(app.name)/releases/latest")! }

    // MARK: instalación

    enum Outcome { case installed, installerOpened, pageOpened }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 1) Homebrew (`brew install --cask jdevesablanco/tap/<app>`) si está; 2) si no (o falla), el último .pkg del Release
    /// de GitHub (API pública, sin token), que se abre con el Instalador; 3) si no hay .pkg, la página del Release.
    static func install(_ app: PackApp) async throws -> Outcome {
        if let brew = brewPath, (try? await runBrew(brew, ["install", "--cask", "\(owner)/tap/\(app.cask)"])) == true {
            return .installed
        }
        if let pkg = try await latestAsset(app, ext: "pkg") {
            let (tmp, _) = try await URLSession.shared.download(from: pkg)
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(pkg.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            await MainActor.run { _ = NSWorkspace.shared.open(dest) }
            return .installerOpened
        }
        await MainActor.run { _ = NSWorkspace.shared.open(releasesPage(app)) }
        return .pageOpened
    }

    private static func runBrew(_ brew: String, _ args: [String]) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: brew)
            p.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "\((brew as NSString).deletingLastPathComponent):/usr/bin:/bin:/usr/sbin:/sbin"
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus == 0) }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let assets: [Asset]
    }

    private static func latestAsset(_ app: PackApp, ext: String) async throws -> URL? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(app.name)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }     // 404 = aún sin versiones publicadas
        let rel = try JSONDecoder().decode(Release.self, from: data)
        return rel.assets.first { $0.name.lowercased().hasSuffix(".\(ext)") }?.browser_download_url
    }
}

/// Estado de las tarjetas: qué está instalado, qué se está instalando y el último mensaje de cada una.
final class PackStore: ObservableObject {
    @Published private(set) var installed: [String: URL] = [:]
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var note: [String: String] = [:]
    private var watch: Timer?

    init() { refresh() }

    func refresh() {
        var m: [String: URL] = [:]
        for a in PackCatalog.apps { if let u = PackCatalog.installedURL(a) { m[a.id] = u } }
        if m != installed { installed = m }
        for id in busy where m[id] != nil { busy.remove(id); note[id] = nil }
        if busy.isEmpty { watch?.invalidate(); watch = nil }
    }

    func install(_ app: PackApp) {
        guard !busy.contains(app.id) else { return }
        busy.insert(app.id)
        note[app.id] = PackCatalog.t("Instalando…", "Installing…")
        Task { @MainActor in
            do {
                switch try await PackCatalog.install(app) {
                case .installed:
                    refresh()
                case .installerOpened:
                    note[app.id] = PackCatalog.t("Sigue los pasos del instalador", "Follow the installer steps")
                    startWatching()
                case .pageOpened:
                    busy.remove(app.id)
                    note[app.id] = PackCatalog.t("Descárgala desde la página que se ha abierto", "Download it from the page that just opened")
                }
            } catch {
                busy.remove(app.id)
                note[app.id] = PackCatalog.t("No se pudo instalar: ", "Couldn't install: ") + error.localizedDescription
            }
        }
    }

    /// Mientras el Instalador está abierto, mira cada 2 s si la app ya apareció (y para cuando aparece).
    private func startWatching() {
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }
}

// MARK: - Vistas

/// Sección «Pairs well with / Combina bien con»: una tarjeta por app de la familia.
struct PackAppsSection: View {
    @ObservedObject var store: PackStore
    var title: String? = nil
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 6) {
                Text(title ?? PackCatalog.t("Combina bien con", "Pairs well with")).font(.headline)
                Text(PackCatalog.t("· hechas por nosotros, gratis y open source", "· made by us, free and open source"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(PackCatalog.apps) { app in PackAppCard(app: app, store: store, compact: compact) }
        }
        .onAppear { store.refresh() }
    }
}

struct PackAppCard: View {
    let app: PackApp
    @ObservedObject var store: PackStore
    var compact = false

    // Una app sin publicar sale como «Próximamente» aunque haya una versión de desarrollo instalada (salvo en sí misma).
    private var url: URL? { app.released || isSelf ? store.installed[app.id] : nil }
    private var isSelf: Bool { app.id == Bundle.main.bundleIdentifier }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(app.name).font(.system(size: 13, weight: .semibold))
                    badge
                }
                Text(PackCatalog.t(app.es, app.en)).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let n = store.note[app.id], url == nil {
                    Text(n).font(.caption2).foregroundStyle(PackCatalog.accent).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(compact ? 9 : 12)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(url != nil ? PackCatalog.accent.opacity(0.08) : Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(url != nil ? PackCatalog.accent.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1))
        .opacity(app.released || url != nil ? 1 : 0.75)
    }

    private var icon: some View {
        let side: CGFloat = compact ? 34 : 40
        return Group {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
            } else {
                Image(systemName: app.symbol).font(.system(size: side * 0.42, weight: .medium)).foregroundStyle(.white)
                    .frame(width: side, height: side)
                    .background(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                        .fill(LinearGradient(colors: [PackCatalog.accent, PackCatalog.accent.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            }
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder private var badge: some View {
        if url != nil {
            pill(PackCatalog.t("Instalada ✓", "Installed ✓"), fill: PackCatalog.accent.opacity(0.85), fg: .white)
            if isSelf { pill(PackCatalog.t("Esta app", "This app"), fill: Color.gray.opacity(0.25), fg: .secondary) }
        } else if !app.released {
            pill(PackCatalog.t("Próximamente", "Coming soon"), fill: Color.gray.opacity(0.25), fg: .secondary)
        }
    }

    private func pill(_ s: String, fill: Color, fg: Color) -> some View {
        Text(s).font(.system(size: 10, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(fill)).foregroundStyle(fg)
    }

    @ViewBuilder private var control: some View {
        if url != nil {
            if !isSelf { Button(PackCatalog.t("Abrir", "Open")) { PackCatalog.open(app) } }
        } else if !app.released {
            Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch).disabled(true)
                .help(PackCatalog.t("Todavía no está publicada", "Not released yet"))
        } else if store.busy.contains(app.id) {
            ProgressView().controlSize(.small)
        } else {
            Button(PackCatalog.t("Instalar", "Install")) { store.install(app) }
                .help(PackCatalog.brewPath != nil ? "brew install --cask \(PackCatalog.owner)/tap/\(app.cask)"
                                                  : PackCatalog.t("Descarga el instalador (.pkg) desde GitHub", "Downloads the installer (.pkg) from GitHub"))
        }
    }
}
