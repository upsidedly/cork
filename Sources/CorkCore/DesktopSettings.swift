import Foundation

public enum WallpaperKind: String, Codable, CaseIterable, Sendable { case system, image, video }

public struct WallpaperSettings: Codable, Equatable, Sendable {
    public var kind: WallpaperKind = .system
    public var assetFile: String?
    public var posterFile: String?
    public var sourceName: String?
    public var paused = false
    public var sourceURL: String?
    public var pixelWidth: Double?
    public var pixelHeight: Double?
    public init() {}

    public func validate() throws {
        func safe(_ name: String) -> Bool {
            !name.isEmpty && !name.hasPrefix(".") && name == URL(fileURLWithPath: name).lastPathComponent
        }
        if kind == .system {
            guard assetFile == nil && posterFile == nil else { throw CorkError("System wallpaper must not reference an imported asset.") }
        } else {
            guard let assetFile, safe(assetFile) else { throw CorkError("Invalid wallpaper filename.") }
            if kind == .image {
                guard ["png", "jpg", "jpeg"].contains(URL(fileURLWithPath: assetFile).pathExtension.lowercased()), posterFile == nil else { throw CorkError("Invalid image wallpaper.") }
            } else {
                guard let posterFile, safe(posterFile), posterFile.hasSuffix(".png") else { throw CorkError("A video wallpaper needs its saved preview.") }
            }
        }
        guard (sourceName?.count ?? 0) <= 500 else { throw CorkError("Wallpaper name is too long.") }
        if let sourceURL { guard sourceURL.count <= 8192, let url = URL(string: sourceURL), url.scheme == "https", url.host != nil else { throw CorkError("Invalid wallpaper source URL.") } }
        if let pixelWidth { guard pixelWidth.isFinite, pixelWidth > 0 else { throw CorkError("Invalid wallpaper width.") } }
        if let pixelHeight { guard pixelHeight.isFinite, pixelHeight > 0 else { throw CorkError("Invalid wallpaper height.") } }
    }
}

public struct DesktopSettings: Codable, Equatable, Sendable {
    public var hideDesktopFiles = true
    public var defaultImageStyle: PrintStyle = .tape
    public var wallpaper = WallpaperSettings()
    public var rotationTheme: String?
    public var controls: DesktopControlSettings?
    public var hideWidgets: Bool?
    public var scenes: SceneOptions?
    public var randomizationSchedule: RandomizationSchedule?
    public var widgetsHidden: Bool { hideWidgets ?? false }
    public var sceneOptions: SceneOptions { scenes ?? SceneOptions() }
    public var desktopControls: DesktopControlSettings { controls ?? DesktopControlSettings() }
    public init() {}
    public func validate() throws {
        guard PrintStyle.imageStyles.contains(defaultImageStyle) else { throw CorkError("Invalid default image style.") }
        guard (rotationTheme?.count ?? 0) <= 80 else { throw CorkError("Invalid rotation theme.") }
        try wallpaper.validate()
        try controls?.validate()
        try scenes?.validate()
        try randomizationSchedule?.validate()
    }
}
