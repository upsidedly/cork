import AppKit
import Carbon
import CorkCore

// Carbon invokes C callbacks without Swift actor isolation. Forward only value IDs.
private func receiveCorkHotKey(_ next: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var value = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &value)
    guard status == noErr, value.signature == 0x43524B4D || value.signature == 0x43524B52 else { return OSStatus(eventNotHandledErr) }
    let id = value.id, signature = value.signature
    DispatchQueue.main.async { GlobalDesktopShortcut.receivers[signature]?(id) }
    return noErr
}

@MainActor final class GlobalDesktopShortcut {
    static var receivers: [UInt32: (UInt32) -> Void] = [:]
    // Carbon permits this callback only once on an application event target.
    // Both shortcuts share it and dispatch by their distinct signatures.
    private static var handler: EventHandlerRef?
    private enum Proposal {
        case disabled
        case unchanged(MinimizeShortcut)
        case registered(EventHotKeyRef, MinimizeShortcut, UInt32)
    }
    private let signature: UInt32
    private var reference: EventHotKeyRef?
    private var active: MinimizeShortcut?
    private var proposal: Proposal?
    private var nextID: UInt32 = 1
    private var activeID: UInt32 = 0
    var onPress: (() -> Void)?
    var isRegistered: Bool { reference != nil }
    init(signature: UInt32) { self.signature = signature }

    private func install() throws {
        if Self.handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), receiveCorkHotKey, 1, &type, nil, &Self.handler)
            guard status == noErr else { throw CorkError("Cork could not install its keyboard shortcut (\(status)).") }
        }
        Self.receivers[signature] = { [weak self] id in
            guard let self, self.activeID == id, self.reference != nil else { return }; self.onPress?()
        }
    }
    /// Keep the old key registered until both proposed bindings and the save succeed.
    func reserve(_ shortcut: MinimizeShortcut?) throws {
        discard()
        guard let shortcut else { proposal = .disabled; return }
        try shortcut.validate()
        if active?.keyCode == shortcut.keyCode, active?.modifiers == shortcut.modifiers, reference != nil { proposal = .unchanged(shortcut); return }
        try install()
        var modifiers: UInt32 = 0
        if shortcut.modifiers & 1 != 0 { modifiers |= UInt32(cmdKey) }
        if shortcut.modifiers & 2 != 0 { modifiers |= UInt32(optionKey) }
        if shortcut.modifiers & 4 != 0 { modifiers |= UInt32(controlKey) }
        if shortcut.modifiers & 8 != 0 { modifiers |= UInt32(shiftKey) }
        var proposed: EventHotKeyRef?
        let id = nextID; nextID &+= 1
        let status = RegisterEventHotKey(shortcut.keyCode, modifiers, EventHotKeyID(signature: signature, id: id),
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &proposed)
        guard status == noErr, let proposed else { throw CorkError("That shortcut is unavailable or already in use. Choose another combination.") }
        proposal = .registered(proposed, shortcut, id)
    }
    func commit() {
        guard let proposal else { return }; self.proposal = nil
        switch proposal {
        case .disabled: unregisterActive()
        case .unchanged(let key): active = key
        case .registered(let new, let key, let id): unregisterActive(); reference = new; active = key; activeID = id
        }
    }
    func discard() {
        if case let .registered(value, _, _) = proposal { UnregisterEventHotKey(value) }; proposal = nil
    }
    func register(_ shortcut: MinimizeShortcut?) throws { try reserve(shortcut); commit() }
    private func unregisterActive() {
        if let reference { UnregisterEventHotKey(reference) }; reference = nil; active = nil; activeID = 0
    }
    func unregister() { discard(); unregisterActive() }
    func stop() {
        unregister(); Self.receivers.removeValue(forKey: signature)
        if Self.receivers.isEmpty, let handler = Self.handler { RemoveEventHandler(handler); Self.handler = nil }
    }
}
