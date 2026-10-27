import AppKit

/// `PIEMENU_SELFTEST=1 PieMenu.app/Contents/MacOS/PieMenu` drives the pie with a simulated pointer and simulated
/// modifier keys, off screen and with a throwaway config, then quits with status 0 (all passed) or 1.
/// It sends no real keyboard or mouse events and registers no global keys, so it never gets in the user's way.
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["PIEMENU_SELFTEST"] != nil else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("piemenu-selftest-\(UUID().uuidString)")
        let marker = dir.appendingPathComponent("ran.txt")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("PIEMENU_CONFIG_DIR", dir.path, 1)

        let store = ConfigStore()
        store.config.slices = ["top", "right", "bottom", "left"].map {
            Slice(name: $0, kind: .shell, target: "echo \($0) >> '\(marker.path)'")
        }
        let pie = PieController(store: store)
        pie.usesSystemInput = false
        let origin = NSPoint(x: -20_000, y: -20_000)   // off every screen
        var pointer = origin
        var held: NSEvent.ModifierFlags = .control
        pie.pointer = { pointer }
        pie.heldModifiers = { held }

        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print(ok ? "✓" : "✗", name)
            if !ok { failures += 1 }
        }
        func ran() -> String { (try? String(contentsOf: marker, encoding: .utf8)) ?? "" }
        func wait(_ seconds: Double, until done: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        func click(_ dx: CGFloat, _ dy: CGFloat) {
            guard let view = pie.view, let window = view.window else { return }
            let p = view.convert(NSPoint(x: view.bounds.midX + dx, y: view.bounds.midY + dy), to: nil)
            if let e = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                view.mouseDown(with: e)
            }
        }

        // 1. Hold ⌃, open, move onto the top slice, let go: highlighted, but nothing runs and the pie stays open.
        pie.toggle()
        check(pie.isShown, "hotkey opens the pie")
        pointer = NSPoint(x: origin.x, y: origin.y + 90)
        pie.tick()
        check(pie.highlighted == 0, "hovering the top slice highlights it")
        pie.toggle()   // key auto-repeat while held
        check(pie.isShown, "auto-repeat while holding the hotkey keeps it open")
        held = []
        pie.tick()
        wait(1) { !ran().isEmpty }
        check(pie.isShown, "letting go over a slice keeps the pie open")
        check(ran().isEmpty, "letting go over a slice runs nothing")

        // 2. Click the top slice: it runs and the pie closes.
        click(0, 90)
        check(!pie.isShown, "clicking a slice closes the pie")
        wait(5) { !ran().isEmpty }
        check(ran() == "top\n", "clicking a slice runs that slice")

        // 3. Click the centre: closes, nothing runs.
        try? FileManager.default.removeItem(at: marker)
        pointer = origin
        held = .control
        pie.toggle()
        held = []
        pie.tick()
        click(0, 0)
        wait(1) { !ran().isEmpty }
        check(!pie.isShown, "clicking the centre closes the pie")
        check(ran().isEmpty, "clicking the centre runs nothing")

        // 4. After letting go, pressing the hotkey again closes it.
        pie.toggle()
        held = []
        pie.tick()
        pie.toggle()
        check(!pie.isShown, "a fresh press of the hotkey closes the pie")

        // 5. Clicking the right slice runs that one, not another.
        pie.toggle()
        held = []
        pie.tick()
        click(90, 0)
        wait(5) { !ran().isEmpty }
        check(ran() == "right\n", "clicking the right slice runs the right slice")

        // 6. The default is "on click"; "on release" is opt-in.
        check(Config().runOnRelease == false, "default is run on click")

        // 7. With "on release": letting go over the bottom slice runs it and closes the pie…
        store.config.runOnRelease = true
        try? FileManager.default.removeItem(at: marker)
        pointer = origin
        held = .control
        pie.toggle()
        pointer = NSPoint(x: origin.x, y: origin.y - 90)
        pie.tick()
        held = []
        pie.tick()
        check(!pie.isShown, "on release: letting go over a slice closes the pie")
        wait(5) { !ran().isEmpty }
        check(ran() == "bottom\n", "on release: letting go over a slice runs it")

        // …letting go in the centre keeps it open, and a click still runs a slice.
        try? FileManager.default.removeItem(at: marker)
        pointer = origin
        held = .control
        pie.toggle()
        held = []
        pie.tick()
        check(pie.isShown, "on release: letting go in the centre keeps it open")
        click(-90, 0)
        wait(5) { !ran().isEmpty }
        check(ran() == "left\n", "on release: clicking still runs a slice")

        try? FileManager.default.removeItem(at: dir)
        print(failures == 0 ? "OK" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
