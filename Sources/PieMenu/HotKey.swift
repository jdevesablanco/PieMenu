import Carbon.HIToolbox

/// A system-wide hotkey registered with Carbon's RegisterEventHotKey.
/// No Accessibility permission is needed, and the key never reaches the frontmost app.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// Returns nil when the combination can't be registered (e.g. another app owns it).
    init?(_ spec: HotKeySpec, action: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        id = HotKey.nextID
        HotKey.nextID += 1
        let hkID = EventHotKeyID(signature: OSType(0x5049_4D4E) /* 'PIMN' */, id: id)
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else { return nil }
        HotKey.handlers[id] = action
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if let handler = HotKey.handlers[hkID.id] {
                DispatchQueue.main.async(execute: handler)
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}
