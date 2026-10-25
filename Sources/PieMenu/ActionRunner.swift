import AppKit

enum ActionRunner {
    static func run(_ slice: Slice) {
        let target = (slice.target as NSString).expandingTildeInPath
        switch slice.kind {
        case .open:
            let url = URL(fileURLWithPath: target)
            if url.pathExtension.lowercased() == "workflow" {
                // Opening a .workflow would just show it in Automator; run it instead.
                launch("/usr/bin/automator", [target], label: slice.name)
            } else if url.pathExtension.lowercased() == "app" {
                let conf = NSWorkspace.OpenConfiguration()
                conf.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: conf) { _, error in
                    if let error { report(slice.name, error.localizedDescription) }
                }
            } else if FileManager.default.fileExists(atPath: target) {
                NSWorkspace.shared.open(url)
            } else {
                report(slice.name, "File not found: \(target)")
            }
        case .shortcut:
            launch("/usr/bin/shortcuts", ["run", slice.target], label: slice.name)
        case .shell:
            launch("/bin/zsh", ["-lc", slice.target], label: slice.name)
        }
    }

    private static func launch(_ exe: String, _ args: [String], label: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        p.standardError = err
        p.terminationHandler = { proc in
            guard proc.terminationStatus != 0 else { return }
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                report(label, msg.isEmpty ? "Exited with status \(proc.terminationStatus)." : msg)
            }
        }
        do { try p.run() } catch { report(label, error.localizedDescription) }
    }

    private static func report(_ label: String, _ message: String) {
        NSLog("PieMenu: \(label): \(message)")
        let alert = NSAlert()
        alert.messageText = "“\(label)” failed"
        alert.informativeText = message.trimmingCharacters(in: .whitespacesAndNewlines)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
