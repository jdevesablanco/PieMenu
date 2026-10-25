import AppKit
import Carbon.HIToolbox

/// Shows the radial menu around the cursor and decides which slice gets run.
///
/// Holding the hotkey's modifiers and letting go over a slice runs it. Letting go in the
/// centre (or tapping the hotkey) leaves the menu open so a slice can be clicked instead.
/// Esc, the hotkey again, a click in the centre or anywhere outside the menu cancels.
final class PieController {
    static let radius: CGFloat = 132
    static let innerRadius: CGFloat = 48

    private let store: ConfigStore
    private var panel: PiePanel?
    private var view: PieView?
    private var timer: Timer?
    private var escKey: HotKey?
    private var clickMonitor: Any?
    private var waitingForRelease = false
    private var releaseModifiers: NSEvent.ModifierFlags = []

    var isShown: Bool { panel?.isVisible == true }

    init(store: ConfigStore) {
        self.store = store
    }

    func toggle() {
        // Holding the hotkey auto-repeats it; only a fresh press after letting go closes the menu.
        if isShown { if !waitingForRelease { dismiss() } } else { show() }
    }

    func show() {
        let slices = Array(store.config.slices.prefix(Config.maxSlices))
        guard !slices.isEmpty else { return }

        let size = (Self.radius + 12) * 2
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var frame = NSRect(x: mouse.x - size / 2, y: mouse.y - size / 2, width: size, height: size)
        if let sf = screen?.frame {
            frame.origin.x = min(max(frame.minX, sf.minX), sf.maxX - size)
            frame.origin.y = min(max(frame.minY, sf.minY), sf.maxY - size)
        }

        let panel = self.panel ?? PiePanel()
        let view = PieView(frame: NSRect(origin: .zero, size: frame.size), slices: slices)
        view.onClick = { [weak self] index in
            if let index { self?.choose(index) } else { self?.dismiss() }
        }
        // Dark glass ring with a see-through hole, like the system HUDs.
        let effect = NSVisualEffectView(frame: view.bounds)
        effect.material = .hudWindow
        effect.appearance = NSAppearance(named: .vibrantDark)
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.maskImage = PieView.ringMask(size: frame.size)
        let container = NSView(frame: view.bounds)
        container.addSubview(effect)
        container.addSubview(view)
        panel.contentView = container
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        self.view = view

        releaseModifiers = store.config.hotKey.cocoaModifiers
        waitingForRelease = !releaseModifiers.isEmpty
        escKey = HotKey(HotKeySpec(keyCode: UInt32(kVK_Escape), modifiers: 0)) { [weak self] in self?.dismiss() }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        escKey = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        panel?.orderOut(nil)
        view = nil
    }

    private func tick() {
        guard let panel, let view else { return }
        let c = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let m = NSEvent.mouseLocation
        view.selected = PieView.sliceIndex(dx: m.x - c.x, dy: m.y - c.y, count: view.slices.count)

        // NSEvent.modifierFlags goes stale while another app is active; ask the window server.
        let held = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        if waitingForRelease, !held.contains(releaseModifiers) {
            waitingForRelease = false
            if let index = view.selected { choose(index) }
        }
    }

    private func choose(_ index: Int) {
        guard let slice = view?.slices[safe: index] else { return }
        dismiss()
        ActionRunner.run(slice)
    }
}

final class PiePanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = .popUpMenu // after isFloatingPanel, which resets the level
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PieView: NSView {
    let slices: [Slice]
    private let icons: [NSImage]
    var onClick: ((Int?) -> Void)?
    var selected: Int? {
        didSet { if selected != oldValue { needsDisplay = true } }
    }

    init(frame: NSRect, slices: [Slice]) {
        self.slices = slices
        self.icons = slices.map { SliceIcon.image(for: $0, size: 128) }
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Slices start at 12 o'clock and go clockwise. nil inside the centre hole.
    static func sliceIndex(dx: CGFloat, dy: CGFloat, count: Int) -> Int? {
        guard count > 0, hypot(dx, dy) > PieController.innerRadius else { return nil }
        let step = 360 / Double(count)
        var rel = 90 - atan2(Double(dy), Double(dx)) * 180 / .pi
        rel = rel.truncatingRemainder(dividingBy: 360)
        if rel < 0 { rel += 360 }
        return Int((rel + step / 2) / step) % count
    }

    static func ringMask(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            let ring = NSBezierPath(ovalIn: circle(c, PieController.radius))
            ring.append(NSBezierPath(ovalIn: circle(c, PieController.innerRadius)))
            ring.windingRule = .evenOdd
            NSColor.black.setFill()
            ring.fill()
            return true
        }
    }

    static func circle(_ c: NSPoint, _ r: CGFloat) -> NSRect {
        NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let dx = p.x - bounds.midX, dy = p.y - bounds.midY
        if hypot(dx, dy) > PieController.radius { onClick?(nil); return }
        onClick?(Self.sliceIndex(dx: dx, dy: dy, count: slices.count))
    }

    var iconSize: CGFloat {
        let ringMid = (PieController.radius + PieController.innerRadius) / 2
        let spacing = 2 * .pi * ringMid / CGFloat(max(slices.count, 4))
        return min(50, spacing * 0.7)
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: bounds.midX, y: bounds.midY)
        let r = PieController.radius, inner = PieController.innerRadius
        let n = slices.count
        let step = 360 / CGFloat(n)

        // A light tint over the glass, a whisper of tint in the hole, and hairline edges.
        let ring = NSBezierPath(ovalIn: Self.circle(c, r))
        ring.append(NSBezierPath(ovalIn: Self.circle(c, inner)))
        ring.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.18).setFill()
        ring.fill()
        NSColor.white.withAlphaComponent(0.05).setFill()
        NSBezierPath(ovalIn: Self.circle(c, inner)).fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        for radius in [r - 0.5, inner + 0.5] {
            let edge = NSBezierPath(ovalIn: Self.circle(c, radius))
            edge.lineWidth = 1
            edge.stroke()
        }

        if let sel = selected {
            drawHighlight(center: c, mid: 90 - CGFloat(sel) * step, span: step)
        }

        let iconRadius = (r + inner) / 2
        let size = iconSize
        for (i, icon) in icons.enumerated() {
            let a = (90 - CGFloat(i) * step) * .pi / 180
            let p = NSPoint(x: c.x + cos(a) * iconRadius, y: c.y + sin(a) * iconRadius)
            icon.draw(in: NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }

        if let sel = selected, let name = slices[safe: sel]?.name, !name.isEmpty {
            drawPill(name, center: c, maxWidth: inner * 2 + 24)
        }
    }

    /// A soft, round-cornered wedge behind the hovered slice.
    private func drawHighlight(center c: NSPoint, mid: CGFloat, span: CGFloat) {
        let corner: CGFloat = 11, pad: CGFloat = 4
        let outerR = PieController.radius - pad - corner
        let innerR = PieController.innerRadius + pad + corner
        // Pull the sides in so the rounded stroke stays inside the slice.
        let outerHalf = span / 2 - asin((pad + corner) / outerR) * 180 / .pi
        let innerHalf = span / 2 - asin(min(1, (pad + corner) / innerR)) * 180 / .pi
        guard outerHalf > 0 else { return }
        let wedge = NSBezierPath()
        wedge.appendArc(withCenter: c, radius: outerR, startAngle: mid + outerHalf, endAngle: mid - outerHalf, clockwise: true)
        if innerHalf > 0 {
            wedge.appendArc(withCenter: c, radius: innerR, startAngle: mid - innerHalf, endAngle: mid + innerHalf, clockwise: false)
        } else {
            let a = mid * .pi / 180
            wedge.line(to: NSPoint(x: c.x + cos(a) * innerR, y: c.y + sin(a) * innerR))
        }
        wedge.close()
        wedge.lineJoinStyle = .round
        wedge.lineWidth = corner * 2

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setAlpha(0.2)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        NSColor.white.set()
        wedge.fill()
        wedge.stroke()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// The hovered slice's name in a light capsule in the centre hole.
    private func drawPill(_ text: String, center c: NSPoint, maxWidth: CGFloat) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.85),
            .paragraphStyle: para,
        ])
        let textW = min(label.size().width, maxWidth - 20)
        let h: CGFloat = 23
        let pill = NSRect(x: c.x - textW / 2 - 10, y: c.y - h / 2, width: textW + 20, height: h)
        NSColor.white.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: pill, xRadius: h / 2, yRadius: h / 2).fill()
        let lh = label.size().height
        label.draw(in: NSRect(x: pill.minX + 10, y: c.y - lh / 2, width: textW, height: lh))
    }
}

enum SliceIcon {
    static func image(for slice: Slice, size: CGFloat) -> NSImage {
        if !slice.icon.isEmpty, let img = tile(slice.icon, size: size) { return img }
        switch slice.kind {
        case .open:
            // Resolve symlinks (e.g. /Applications/Safari.app) so the icon has no alias badge.
            let path = URL(fileURLWithPath: (slice.target as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
            if FileManager.default.fileExists(atPath: path) {
                let img = NSWorkspace.shared.icon(forFile: path)
                img.size = NSSize(width: size, height: size)
                return img
            }
            return tile("questionmark", size: size)!
        case .shortcut:
            let img = NSWorkspace.shared.icon(forFile: "/System/Applications/Shortcuts.app")
            img.size = NSSize(width: size, height: size)
            return img
        case .shell:
            return tile("terminal.fill", size: size)!
        }
    }

    /// An SF Symbol on a rounded-square tile, sized and inset like a macOS app icon.
    static func tile(_ name: String, size: CGFloat) -> NSImage? {
        let conf = NSImage.SymbolConfiguration(pointSize: size * 0.36, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(conf) else { return nil }
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // App icons leave ~10% transparent margin around the squircle.
            let body = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
            let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.height * 0.225)
            NSGradient(starting: NSColor(white: 0.42, alpha: 1), ending: NSColor(white: 0.22, alpha: 1))!
                .draw(in: shape, angle: -90)
            NSColor.white.withAlphaComponent(0.12).setStroke()
            shape.lineWidth = 1
            shape.stroke()
            let s = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
            return true
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
