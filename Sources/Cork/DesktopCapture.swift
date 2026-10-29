import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import CorkCore

@MainActor
enum DesktopCapture {
    static func capture(display: DisplayInfo, mode: String, maxWidth: Int,
                        printWindows: Set<Int>, root: URL) async throws -> JSONValue {
        guard CGPreflightScreenCaptureAccess() else {
            throw CorkError("Screen Recording is not allowed for Cork. Open Cork's library → Settings → Allow Screen Recording, enable Cork in System Settings, then relaunch it if macOS asks. Adding and arranging images does not require this permission.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.displays.first(where: { $0.displayID == display.id }) else { throw CorkError("This display is no longer connected.") }
        let excluded = mode == "desktop" ? content.windows.filter { window in
            !printWindows.contains(Int(window.windowID)) && window.windowLayer >= 0
        } : []
        let filter = SCContentFilter(display: target, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        configuration.width = maxWidth
        configuration.height = Int((Double(maxWidth) * display.height / display.width).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw CorkError("Could not encode the desktop screenshot.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CorkError("Could not finish the desktop screenshot.") }
        let png = data as Data
        let directory = root.appendingPathComponent("Captures", isDirectory: true)
        let path = directory.appendingPathComponent("desktop-\(UUID().uuidString).png")
        try await Task.detached {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try png.write(to: path, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        }.value
        let metadata: JSONValue = .object([
            "path": .string(path.path), "mode": .string(mode), "display_id": .number(Double(display.id)),
            "pixel_width": .number(Double(image.width)), "pixel_height": .number(Double(image.height)),
            "points_width": .number(display.width), "points_height": .number(display.height),
            "pixels_per_point": .number(Double(image.width) / display.width)
        ])
        let text = String(decoding: try metadata.data(pretty: true), as: UTF8.self)
        return .object(["content": .array([
            .object(["type": .string("text"), "text": .string(text)]),
            .object(["type": .string("image"), "mimeType": .string("image/png"), "data": .string(png.base64EncodedString())])
        ]), "isError": .bool(false)])
    }
}
