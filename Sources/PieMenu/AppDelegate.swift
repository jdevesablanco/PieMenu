import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = ConfigStore()
    lazy var pie = PieController(store: store)
    lazy var settings = SettingsModel(store: store, app: self)

    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Snapshot.runIfRequested(store: store)
        SelfTest.runIfRequested()
        PackCatalog.isSpanish = { Lang.isSpanish }
        pie.onOpenSettings = { [weak self] id in
            guard let self else { return }
            if let id { self.settings.selectedID = id; self.settings.tab = 0 }
            self.openSettings()
        }
        NSApp.mainMenu = Self.mainMenu()

        store.$config
            .map(\.hotKey)
            .removeDuplicates()
            .sink { [weak self] spec in self?.registerHotKey(spec) }
            .store(in: &cancellables)
        store.$config
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] show in self?.setStatusItem(visible: show) }
            .store(in: &cancellables)

        // Without the menu bar icon, opening the app yourself (Finder, Spotlight, Launchpad) is the way into Settings.
        // Not when macOS starts it at login.
        let defaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? true
        if ProcessInfo.processInfo.arguments.contains("--settings")
            || (!store.config.showMenuBarIcon && defaultLaunch && !launchedAtLogin()) {
            openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func setStatusItem(visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "PieMenu")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Did macOS launch us at login? The open event says so; as a fallback (SMAppService doesn't always set it),
    /// assume so if the session started less than 2 minutes ago.
    private func launchedAtLogin() -> Bool {
        if let ev = NSAppleEventManager.shared().currentAppleEvent, ev.eventID == AEEventID(kAEOpenApplication),
           let d = ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)), d.enumCodeValue == OSType(keyAELaunchedAsLogInItem) { return true }
        if let lw = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").first?.launchDate,
           Date().timeIntervalSince(lw) < 120 { return true }
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
