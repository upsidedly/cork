import AppKit

/// The native wallpaper supplies macOS's menu-bar tint; desktop windows do not.
struct SystemWallpaperImage: Codable, Equatable {
    var url: URL
    var scaling: UInt?
    var clipping: Bool?
    var fill: [Double]?

    static func cover(_ url: URL) -> Self {
        Self(url: url.standardizedFileURL, scaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
             clipping: true, fill: [0, 0, 0, 1])
    }

    var isValid: Bool {
        guard url.isFileURL, url.path.count <= 8192 else { return false }
        if let scaling, NSImageScaling(rawValue: scaling) == nil { return false }
        if let fill, fill.count != 4 || !fill.allSatisfy({ $0.isFinite && (0...1).contains($0) }) { return false }
        return true
    }
}

@MainActor protocol SystemWallpaperAccess {
    var displayIDs: [UInt32] { get }
    func image(for displayID: UInt32) -> SystemWallpaperImage?
    func setImage(_ image: SystemWallpaperImage, for displayID: UInt32) throws
}

@MainActor final class MacSystemWallpaperAccess: SystemWallpaperAccess {
    private func screen(_ id: UInt32) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }
    var displayIDs: [UInt32] {
        NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
    }
    func image(for displayID: UInt32) -> SystemWallpaperImage? {
        guard let screen = screen(displayID), let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let color = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
        return SystemWallpaperImage(url: url.standardizedFileURL,
            scaling: (options[.imageScaling] as? NSNumber)?.uintValue,
            clipping: (options[.allowClipping] as? NSNumber)?.boolValue,
            fill: color.map { [Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent), Double($0.alphaComponent)] })
    }
    func setImage(_ image: SystemWallpaperImage, for displayID: UInt32) throws {
        guard let screen = screen(displayID), image.isValid else { throw SystemWallpaperSync.failure("This wallpaper display is no longer available.") }
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        if let scaling = image.scaling { options[.imageScaling] = scaling }
        if let clipping = image.clipping { options[.allowClipping] = clipping }
        if let fill = image.fill { options[.fillColor] = NSColor(srgbRed: fill[0], green: fill[1], blue: fill[2], alpha: fill[3]) }
        try NSWorkspace.shared.setDesktopImageURL(image.url, for: screen, options: options)
    }
}

/// A small write-ahead journal preserves the original even if Cork exits between
/// setting the system image and saving the result. External user changes win on quit.
@MainActor final class SystemWallpaperSync {
    private struct Lease: Codable, Equatable {
        var original: SystemWallpaperImage
        var applied: SystemWallpaperImage?
        var pending: SystemWallpaperImage?
        func owns(_ image: SystemWallpaperImage) -> Bool { image == applied || image == pending }
    }
    private struct Journal: Codable {
        var schemaVersion = 1
        var displays: [UInt32: Lease] = [:]
    }
    private let access: any SystemWallpaperAccess
    private let journalURL: URL
    private var journal = Journal()
    private var loadFailure: Error?

    init(journalURL: URL, access: any SystemWallpaperAccess = MacSystemWallpaperAccess()) {
        self.journalURL = journalURL; self.access = access
        if FileManager.default.fileExists(atPath: journalURL.path) {
            do {
                let info = try journalURL.resourceValues(forKeys: [.fileSizeKey])
                guard (info.fileSize ?? Int.max) <= 131_072 else { throw Self.failure("Cork's wallpaper recovery record is too large.") }
                let saved = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
                guard saved.schemaVersion == 1, saved.displays.count <= 32,
                      saved.displays.values.allSatisfy({ $0.original.isValid && ($0.applied?.isValid ?? true) && ($0.pending?.isValid ?? true) }) else {
                    throw Self.failure("Cork could not read its wallpaper recovery record.")
                }
                journal = saved
            } catch { loadFailure = error }
        }
    }

    var synchronized: Bool {
        let connected = access.displayIDs
        return !connected.isEmpty && connected.allSatisfy { id in
            guard let lease = journal.displays[id] else { return false }
            return lease.pending == nil && lease.applied != nil && access.image(for: id) == lease.applied
        }
    }

    func apply(_ url: URL, displays: [UInt32]) throws {
        if let loadFailure { throw loadFailure }
        let desired = SystemWallpaperImage.cover(url)
        guard desired.isValid else { throw Self.failure("Choose a local wallpaper image.") }
        for id in displays {
            guard let current = access.image(for: id) else { throw Self.failure("Cork could not read the original system wallpaper. It was left unchanged.") }
            var lease = journal.displays[id] ?? Lease(original: current)
            // An image changed outside Cork becomes the new restoration target.
            if !lease.owns(current) { lease.original = current }
            if current == desired && lease.applied == desired && lease.pending == nil { continue }
            lease.pending = desired
            var next = journal; next.displays[id] = lease
            try save(next); journal = next
            try access.setImage(desired, for: id)
            lease.applied = desired; lease.pending = nil
            next.displays[id] = lease
            try save(next); journal = next
        }
    }

    func restore() throws {
        if let loadFailure { throw loadFailure }
        var firstFailure: Error?
        for id in access.displayIDs {
            guard let lease = journal.displays[id] else { continue }
            do {
                guard let current = access.image(for: id) else { throw Self.failure("Cork could not read the system wallpaper for restoration.") }
                if lease.owns(current) { try access.setImage(lease.original, for: id) }
                var next = journal; next.displays.removeValue(forKey: id)
                try save(next); journal = next
            } catch { if firstFailure == nil { firstFailure = error } }
        }
        if let firstFailure { throw firstFailure }
    }

    private func save(_ next: Journal) throws {
        let files = FileManager.default
        if next.displays.isEmpty {
            if files.fileExists(atPath: journalURL.path) { try files.removeItem(at: journalURL) }
            return
        }
        try files.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(next).write(to: journalURL, options: [.atomic])
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "Cork.SystemWallpaper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
