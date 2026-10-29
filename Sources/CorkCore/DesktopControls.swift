import Foundation

public struct MinimizeShortcut: Codable, Equatable, Sendable {
    // App-owned bits, independent of NSEvent/Carbon: command, option, control, shift.
    public var keyCode: UInt32 = 46
    public var modifiers: UInt32 = 7
    public var keyLabel = "M"
    public init(keyCode: UInt32 = 46, modifiers: UInt32 = 7, keyLabel: String = "M") {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    public var display: String {
        [(UInt32(4), "⌃"), (2, "⌥"), (8, "⇧"), (1, "⌘")].compactMap { modifiers & $0.0 != 0 ? $0.1 : nil }.joined() + keyLabel
    }
    public func validate() throws {
        guard keyCode <= 127, modifiers <= 15, modifiers & 7 != 0,
              !keyLabel.isEmpty, keyLabel.count <= 24, !keyLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CorkError("Use a key together with Command, Option or Control.")
        }
    }
}

public struct RandomizeShortcutOptions: Codable, Equatable, Sendable {
    public var enabled = true
    public var shortcut = MinimizeShortcut(keyCode: 15, modifiers: 7, keyLabel: "R")
    public init() {}
}
public struct DesktopControlSettings: Codable, Equatable, Sendable {
    public var shortcutEnabled = true
    public var shortcut = MinimizeShortcut()
    public var anchoredSwipeEnabled = true
    public var randomize: RandomizeShortcutOptions?
    public var wallShortcut: RandomizeShortcutOptions { randomize ?? RandomizeShortcutOptions() }
    public init() {}
    public func validate() throws { try shortcut.validate(); try wallShortcut.shortcut.validate() }
}

public struct TrackpadContact: Sendable, Equatable {
    public let id: Int32
    public let x: Double
    public let y: Double
    public init(id: Int32, x: Double, y: Double) { self.id = id; self.x = x; self.y = y }
}

/// Requires two fingers to settle first, then only the third to move down.
/// A completed or rejected three-finger sequence stays latched until all fingers lift.
public struct AnchoredSwipeDetector: Sendable {
    private enum Phase: Sendable {
        case idle
        case settling([TrackpadContact], Double)
        case armed([TrackpadContact])
        case swiping([TrackpadContact], TrackpadContact, Double)
        case latched
    }
    private var phase = Phase.idle
    private var device: UInt64?
    private var lastTime: Double?
    public init() {}
    public mutating func reset() { phase = .idle; device = nil; lastTime = nil }

    public mutating func process(device: UInt64, contacts: [TrackpadContact], time: Double) -> Bool {
        guard time.isFinite, time >= 0, contacts.count <= 10, Set(contacts.map(\.id)).count == contacts.count,
              contacts.allSatisfy({ $0.id >= 0 && $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { reset(); return false }
        if self.device != device || (lastTime.map { time < $0 } ?? false) { reset() }
        self.device = device; lastTime = time
        if contacts.isEmpty { phase = .idle; return false }
        func stable(_ anchors: [TrackpadContact]) -> Bool {
            anchors.allSatisfy { anchor in
                contacts.contains { $0.id == anchor.id && hypot($0.x - anchor.x, $0.y - anchor.y) <= 0.035 }
            }
        }
        switch phase {
        case .idle:
            if contacts.count == 2 { phase = .settling(contacts, time) }
            else if contacts.count >= 3 { phase = .latched }
        case let .settling(anchors, since):
            if contacts.count == 2 {
                if !stable(anchors) { phase = .settling(contacts, time) }
                else if time - since >= 0.15 { phase = .armed(anchors) }
            } else if contacts.count == 3, stable(anchors), time - since >= 0.15,
                      let third = contacts.first(where: { candidate in !anchors.contains { $0.id == candidate.id } }) {
                phase = .swiping(anchors, third, time)
            } else { phase = contacts.count >= 3 ? .latched : .idle }
        case let .armed(anchors):
            if contacts.count == 2 {
                if !stable(anchors) { phase = .settling(contacts, time) }
            } else if contacts.count == 3, stable(anchors),
                      let third = contacts.first(where: { candidate in !anchors.contains { $0.id == candidate.id } }) {
                phase = .swiping(anchors, third, time)
            } else { phase = contacts.count >= 3 ? .latched : .idle }
        case let .swiping(anchors, start, since):
            guard contacts.count == 3, stable(anchors), time - since <= 0.8,
                  let third = contacts.first(where: { $0.id == start.id }) else { phase = .latched; return false }
            let dx = abs(third.x - start.x), dy = third.y - start.y
            if dy > 0.04 || dx > 0.10 { phase = .latched }
            else if dy <= -0.16 && -dy >= dx * 2.5 {
                phase = .latched; return true
            }
        case .latched: break
        }
        return false
    }
}
