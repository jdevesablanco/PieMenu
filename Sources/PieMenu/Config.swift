import AppKit
import Carbon.HIToolbox

/// What a slice does when chosen.
enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case open       // app, file, folder, Automator .app or .workflow
    case shortcut   // Shortcuts.app shortcut, by name
    case shell      // shell command run with zsh

    var id: String { rawValue }
    var label: String {
        switch self {
        case .open: return tr("Abrir app, archivo o carpeta", "Open app, file or folder")
        case .shortcut: return tr("Ejecutar atajo", "Run shortcut")
        case .shell: return tr("Ejecutar comando de shell", "Run shell command")
        }
    }
}

struct Slice: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// SF Symbol name. Empty → the file's own icon for `.open`, a default symbol otherwise.
    var icon: String = ""
    var kind: ActionKind
    /// Path for `.open`, shortcut name for `.shortcut`, command for `.shell`.
    var target: String
}

struct HotKeySpec: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32

    static let controlTab = HotKeySpec(keyCode: UInt32(kVK_Tab), modifiers: UInt32(controlKey))

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }

    /// The same modifiers as Cocoa flags, used to notice when the user lets go.
    var cocoaModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        return f
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }
}

enum AppLanguage: String, Codable, CaseIterable {
    case auto, es, en
}

enum Lang {
    /// Language picked in Settings. `.auto` follows the system.
    static var forced: AppLanguage = .auto
    static var isSpanish: Bool {
        switch forced {
        case .es: return true
        case .en: return false
        case .auto: return (Locale.preferredLanguages.first ?? "en").hasPrefix("es")
        }
    }
}

/// Minimal bilingual text: Spanish or English, following the language setting.
func tr(_ es: String, _ en: String) -> String { Lang.isSpanish ? es : en }

struct Config: Codable, Equatable {
    var hotKey: HotKeySpec = .controlTab
    var slices: [Slice] = Config.defaultSlices
    var language: AppLanguage = .auto
    var showMenuBarIcon = true
    /// false (default): a slice runs only when clicked. true: letting go of the hotkey over a slice also runs it.
    var runOnRelease = false

    init() {}

    /// Missing keys fall back to their defaults, so older config files keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = try c.decodeIfPresent(HotKeySpec.self, forKey: .hotKey) ?? .controlTab
        slices = try c.decodeIfPresent([Slice].self, forKey: .slices) ?? Config.defaultSlices
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .auto
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        runOnRelease = try c.decodeIfPresent(Bool.self, forKey: .runOnRelease) ?? false
    }

    static let defaultSlices: [Slice] = [
        Slice(name: "Finder", kind: .open, target: "/System/Library/CoreServices/Finder.app"),
        Slice(name: "Downloads", kind: .open, target: NSHomeDirectory() + "/Downloads"),
        Slice(name: "Safari", kind: .open, target: "/Applications/Safari.app"),
        Slice(name: "Shortcuts", kind: .open, target: "/System/Applications/Shortcuts.app"),
    ]
    static let maxSlices = 8
}

/// Loads and saves the config as JSON in Application Support (or `PIEMENU_CONFIG_DIR`).
final class ConfigStore: ObservableObject {
    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            Lang.forced = config.language
            save()
        }
    }

    let fileURL: URL

    init() {
        let dir: URL
        if let custom = ProcessInfo.processInfo.environment["PIEMENU_CONFIG_DIR"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PieMenu", isDirectory: true)
        }
        fileURL = dir.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(Config.self, from: data) {
            config = loaded
        } else {
            config = Config()
            save()
        }
        Lang.forced = config.language
    }

    func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(config).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("PieMenu: could not save config: \(error)")
        }
    }
}

enum KeyNames {
    static func name(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "⌫"
        case kVK_ANSI_Grave: return "`"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: break
        }
        // Ask the current keyboard layout for the character.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
