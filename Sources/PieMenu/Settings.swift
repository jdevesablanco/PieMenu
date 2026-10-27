import AppKit
import ServiceManagement
import SwiftUI

final class SettingsModel: ObservableObject {
    let store: ConfigStore
    unowned let app: AppDelegate

    @Published var selectedID: UUID?
    @Published var tab = 0
    @Published var recording = false
    @Published var hotKeyError: String?
    @Published var shortcutNames: [String] = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?

    private var recordMonitor: Any?

    init(store: ConfigStore, app: AppDelegate) {
        self.store = store
        self.app = app
        selectedID = store.config.slices.first?.id
    }

    var selectedIndex: Int? {
        store.config.slices.firstIndex { $0.id == selectedID }
    }

    func addSlice() {
        guard store.config.slices.count < Config.maxSlices else { return }
        let s = Slice(name: tr("Nueva porción", "New slice"), kind: .open, target: "")
        store.config.slices.append(s)
        selectedID = s.id
    }

    func removeSelected() {
        guard let i = selectedIndex else { return }
        store.config.slices.remove(at: i)
        selectedID = store.config.slices[safe: min(i, store.config.slices.count - 1)]?.id
    }

    func moveSelected(by offset: Int) {
        guard let i = selectedIndex, store.config.slices.indices.contains(i + offset) else { return }
        store.config.slices.swapAt(i, i + offset)
    }

    func chooseFile(for index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = tr("Elige una app, una app o flujo de Automator, un archivo o una carpeta",
                           "Choose an app, Automator app or workflow, file or folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var slice = store.config.slices[index]
        slice.target = url.path
        if slice.name.isEmpty || ["New slice", "Nueva porción"].contains(slice.name) {
            slice.name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        store.config.slices[index] = slice
    }

    func refreshShortcuts() {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["list"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let names = (String(data: data, encoding: .utf8) ?? "")
                .split(separator: "\n").map(String.init).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            DispatchQueue.main.async { self.shortcutNames = names }
        }
    }

    func startRecording() {
        guard !recording else { return }
        recording = true
        app.suspendHotKey()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.keyCode == 53, flags.isEmpty { // Esc cancels
                self.stopRecording()
                return nil
            }
            let isFunctionKey = (122...127).contains(event.keyCode) || (96...111).contains(event.keyCode)
            guard !flags.isEmpty || isFunctionKey else { NSSound.beep(); return nil }
            self.stopRecording()
            self.store.config.hotKey = HotKeySpec(keyCode: UInt32(event.keyCode),
                                                  modifiers: HotKeySpec.carbonModifiers(from: flags))
            self.app.resumeHotKey()
            return nil
        }
    }

    func stopRecording() {
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
        recording = false
        app.resumeHotKey()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

extension Color {
    /// Purple accent shared by the pack.
    static let brand = Color(red: 0.50, green: 0.30, blue: 0.93)
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var store: ConfigStore
    @StateObject private var pack = PackStore()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                tabButton(0, tr("Porciones", "Slices"), "circle.circle")
                tabButton(1, tr("General", "General"), "keyboard")
                tabButton(2, tr("Combina bien con", "Pairs well with"), "puzzlepiece.extension")
                Spacer()
                LanguageSwitch(store: store)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            Group {
                switch model.tab {
                case 0: slicesTab
                case 1: generalTab
                default: ScrollView { PackAppsSection(store: pack).padding(18).id(store.config.language) }  // redraw on ES/EN
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 660, minHeight: 460)
        .tint(Color.brand)
    }

    private func tabButton(_ i: Int, _ title: String, _ symbol: String) -> some View {
        Button { model.tab = i } label: {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(model.tab == i ? Color.white : Color.primary)
                .background(Capsule().fill(model.tab == i ? Color.brand : Color.clear))
                .contentShape(Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: Slices

    private var slicesTab: some View {
        HStack(spacing: 0) {
            sliceList.frame(width: 220)
            Divider()
            editor.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sliceList: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedID) {
                ForEach(store.config.slices) { slice in
                    HStack(spacing: 8) {
                        Image(nsImage: SliceIcon.listImage(for: slice))
                            .resizable().frame(width: 20, height: 20)
                        Text(slice.name.isEmpty ? tr("Sin nombre", "Untitled") : slice.name)
                    }
                    .tag(slice.id)
                }
                .onMove { from, to in store.config.slices.move(fromOffsets: from, toOffset: to) }
            }
            Divider()
            HStack(spacing: 4) {
                Button(action: model.addSlice) { Image(systemName: "plus") }
                    .disabled(store.config.slices.count >= Config.maxSlices)
                    .help(tr("Añadir porción (hasta \(Config.maxSlices))", "Add slice (up to \(Config.maxSlices))"))
                Button(action: model.removeSelected) { Image(systemName: "minus") }
                    .disabled(model.selectedIndex == nil)
                    .help(tr("Quitar porción", "Remove slice"))
                Spacer()
                Button { model.moveSelected(by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled((model.selectedIndex ?? 0) == 0)
                    .help(tr("Subir (sentido antihorario)", "Move up (counter-clockwise)"))
                Button { model.moveSelected(by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(model.selectedIndex.map { $0 >= store.config.slices.count - 1 } ?? true)
                    .help(tr("Bajar (sentido horario)", "Move down (clockwise)"))
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder private var editor: some View {
        if let i = model.selectedIndex {
            let slice = Binding(
                get: { store.config.slices[safe: i] ?? Slice(name: "", kind: .open, target: "") },
                set: { if store.config.slices.indices.contains(i) { store.config.slices[i] = $0 } })
            Form {
                TextField(tr("Nombre", "Name"), text: slice.name)
                HStack {
                    TextField(tr("Icono (SF Symbol)", "Icon (SF Symbol)"), text: slice.icon, prompt: Text(tr("Automático", "Automatic")))
                    Image(nsImage: SliceIcon.listImage(for: slice.wrappedValue))
                        .resizable().frame(width: 22, height: 22)
                }
                Picker(tr("Acción", "Action"), selection: slice.kind) {
                    ForEach(ActionKind.allCases) { Text($0.label).tag($0) }
                }
                switch slice.wrappedValue.kind {
                case .open:
                    HStack {
                        TextField(tr("Ruta", "Path"), text: slice.target, prompt: Text("/Applications/…"))
                        Button(tr("Elegir…", "Choose…")) { model.chooseFile(for: i) }
                    }
                    Text(tr("Las apps de Automator se abren como cualquier app; los archivos .workflow se ejecutan con la herramienta automator.",
                            "Automator apps open like any app; .workflow files are run with the automator tool."))
                        .font(.caption).foregroundColor(.secondary)
                case .shortcut:
                    HStack {
                        TextField(tr("Nombre del atajo", "Shortcut name"), text: slice.target)
                        Menu(tr("Elegir", "Pick")) {
                            ForEach(model.shortcutNames, id: \.self) { name in
                                Button(name) { slice.wrappedValue.target = name }
                            }
                        }
                        .fixedSize()
                        .disabled(model.shortcutNames.isEmpty)
                    }
                case .shell:
                    TextField(tr("Comando", "Command"), text: slice.target, prompt: Text("open -a Notes"))
                    Text(tr("Se ejecuta con zsh -lc, así que tienes tu PATH de inicio de sesión.",
                            "Runs with zsh -lc, so your login PATH is available."))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
        } else {
            Text(store.config.slices.isEmpty ? tr("Añade una porción con +", "Add a slice with +") : tr("Elige una porción", "Select a slice"))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Cómo se abre", "How it opens")).font(.title3.bold())
            row(tr("Atajo global", "Global shortcut"),
                tr("Abre el menú junto al puntero; haz clic en una porción para ejecutarla. Pasar el ratón por encima solo la resalta. Funciona en cualquier app, sin permisos especiales.",
                   "Opens the menu at the pointer; click a slice to run it. Hovering only highlights it. Works in any app, no special permissions.")) {
                HStack(spacing: 8) {
                    Button(model.recording ? tr("Pulsa las teclas… (Esc cancela)", "Press keys… (Esc to cancel)") : store.config.hotKey.display) {
                        model.recording ? model.stopRecording() : model.startRecording()
                    }
                    .frame(minWidth: 90)
                    Button(tr("Restablecer", "Reset")) { store.config.hotKey = .controlTab }
                        .disabled(store.config.hotKey == .controlTab)
                }
            }
            if let err = model.hotKeyError {
                Text(err)
                    .font(.caption).foregroundColor(.red)
            }
            row(tr("Mostrar en la barra de menús", "Show in menu bar"),
                tr("Sin el icono, el atajo sigue funcionando. Para volver a estos Ajustes, abre PieMenu otra vez desde Spotlight, Launchpad o Aplicaciones.",
                   "Without the icon the hotkey keeps working. To get back to these Settings, open PieMenu again from Spotlight, Launchpad or Applications.")) {
                Toggle("", isOn: $store.config.showMenuBarIcon).labelsHidden().toggleStyle(.switch)
            }
            row(tr("Abrir al iniciar sesión", "Open at login"), tr("Así el atajo está listo siempre.", "Keeps the hotkey ready at all times.")) {
                Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
            if let err = model.loginError {
                Text(err).font(.caption).foregroundColor(.red)
            }
            Spacer()
            Text(tr("Ajustes guardados en ", "Settings saved in ") + store.fileURL.path)
                .font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
        }
        .padding(18)
    }

    private func row<C: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
    }
}

/// ES/EN switch shown at the top right, like the other apps of the pack.
struct LanguageSwitch: View {
    @ObservedObject var store: ConfigStore
    @Namespace private var ns

    private func seg(_ title: String, es: Bool) -> some View {
        let selected = Lang.isSpanish == es
        return Button { withAnimation(.easeInOut(duration: 0.18)) { store.config.language = es ? .es : .en } } label: {
            Text(title).font(.system(size: 11, weight: .semibold))
                .frame(width: 32, height: 22)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(nsColor: .controlColor))
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                            .matchedGeometryEffect(id: "sel", in: ns)
                    }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 0) { seg("ES", es: true); seg("EN", es: false) }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.gray.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
            .help(tr("Idioma: español / inglés", "Language: Spanish / English"))
    }
}

extension SliceIcon {
    /// Icons in the settings list are drawn on a light background, so symbols use the label colour.
    static func listImage(for slice: Slice) -> NSImage {
        if !slice.icon.isEmpty, let img = NSImage(systemSymbolName: slice.icon, accessibilityDescription: nil) {
            return img
        }
        if slice.kind == .shell { return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)! }
        return image(for: slice, size: 20)
    }
}
