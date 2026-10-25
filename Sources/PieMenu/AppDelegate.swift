import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ConfigStore()
    lazy var pie = PieController(store: store)
    lazy var settings = SettingsModel(store: store, app: self)

    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Snapshot.runIfRequested(store: store)
        PackCatalog.isSpanish = { Lang.isSpanish }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "PieMenu")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        NSApp.mainMenu = Self.mainMenu()

        store.$config
            .map(\.hotKey)
            .removeDuplicates()
            .sink { [weak self] spec in self?.registerHotKey(spec) }
            .store(in: &cancellables)

        if ProcessInfo.processInfo.arguments.contains("--settings") { openSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func registerHotKey(_ spec: HotKeySpec) {
        hotKey = nil
        hotKey = HotKey(spec) { [weak self] in self?.pie.toggle() }
        settings.hotKeyError = hotKey == nil
            ? tr("No se pudo registrar \(spec.display). Puede que otra app ya lo use.",
                 "Couldn't register \(spec.display). Another app may already use it.")
            : nil
    }

    /// While the settings window records a new hotkey the old one must not swallow the keys.
    func suspendHotKey() { hotKey = nil }
    func resumeHotKey() { registerHotKey(store.config.hotKey) }

    /// Rebuilt each time so it follows the language setting.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: tr("Mostrar menú circular", "Show Pie"), action: #selector(showPie), keyEquivalent: "").target = self
        menu.addItem(withTitle: tr("Ajustes…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: tr("Salir de PieMenu", "Quit PieMenu"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Not shown (the app has no Dock icon) but gives the settings text fields ⌘C/⌘V/⌘W.
    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit PieMenu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(appItem)
        main.addItem(editItem)
        return main
    }

    @objc func showPie() {
        // Let the status menu close first so the pie appears at the cursor.
        DispatchQueue.main.async { self.pie.show() }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "PieMenu"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: settings, store: store))
            w.center()
            settingsWindow = w
        }
        settings.refreshShortcuts()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
