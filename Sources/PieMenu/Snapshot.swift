import AppKit

/// `PIEMENU_SNAPSHOT=/dir` renders the pie (with the current config) to PNG and quits; used for the README images.
/// Off-screen there is no live blur, so a dark tint over a sample wallpaper stands in for the glass.
enum Snapshot {
    static func runIfRequested(store: ConfigStore) {
        guard let dir = ProcessInfo.processInfo.environment["PIEMENU_SNAPSHOT"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let slices = Array(store.config.slices.prefix(Config.maxSlices))
        let side = (PieController.radius + 12) * 2
        let size = NSSize(width: side + 80, height: side + 80)
        let view = PieView(frame: NSRect(x: 0, y: 0, width: side, height: side), slices: slices)
        view.selected = slices.count > 1 ? 1 : 0
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: NSColor(red: 0.10, green: 0.33, blue: 0.75, alpha: 1),
                       ending: NSColor(red: 0.36, green: 0.70, blue: 0.56, alpha: 1))!.draw(in: rect, angle: 20)
            let origin = NSPoint(x: (rect.width - side) / 2, y: (rect.height - side) / 2)
            let ring = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
                NSColor(red: 0.08, green: 0.18, blue: 0.20, alpha: 0.8).setFill()
                r.fill()
                PieView.ringMask(size: r.size).draw(in: r, from: .zero, operation: .destinationIn, fraction: 1)
                return true
            }
            ring.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.current?.cgContext.translateBy(x: origin.x, y: origin.y)
            view.draw(view.bounds)
            return true
        }
        // Retina-sized PNG.
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("pie.png"))
        print("✓ \(dir)/pie.png")
        exit(0)
    }
}
