import Foundation

/// The cover remains an ordinary PNG asset. Playback uses a separate, owned local file.
public struct VideoAttachment: Codable, Equatable, Sendable {
    public var file: String
    public var duration: Double
    public var posterTime: Double
    public var colourSamples: [ImageColourProfile]

    public init(file: String, duration: Double, posterTime: Double, colourSamples: [ImageColourProfile]) {
        self.file = file; self.duration = duration; self.posterTime = posterTime; self.colourSamples = colourSamples
    }
    public func validate() throws {
        guard file == URL(fileURLWithPath: file).lastPathComponent, !file.hasPrefix("."),
              ["mp4", "mov", "m4v"].contains(URL(fileURLWithPath: file).pathExtension.lowercased()),
              duration.isFinite, duration > 0, duration <= 600,
              posterTime.isFinite, posterTime >= 0, posterTime < duration,
              (1...5).contains(colourSamples.count) else { throw CorkError("Invalid local video, duration or colour samples.") }
        for sample in colourSamples { try sample.validate() }
    }
    public func matches(_ pair: [ColourFamily], strength: ColourSelectionStrength) -> Bool {
        colourSamples.allSatisfy { $0.matches(pair, strength: strength) }
    }
    public func matches(scheme: ColourScheme) -> Bool {
        let families = Set((scheme.majorColours ?? scheme.colours).compactMap(ColourMatch.lab).map(ColourFamily.classify))
        return colourSamples.allSatisfy { sample in
            let selected = sample.colours.filter { families.contains($0.family) && !$0.family.isNeutral }.reduce(0) { $0 + $1.coverage }
            let foreign = sample.colours.filter { !families.contains($0.family) && !$0.family.isNeutral }.reduce(0) { $0 + $1.coverage }
            return foreign <= (families.allSatisfy(\.isNeutral) ? 0.06 : max(0.08, selected * 0.8))
        }
    }
}
