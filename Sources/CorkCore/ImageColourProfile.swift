import Foundation
import CoreGraphics

public enum ColourFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, teal, blue, violet, pink, brown, cream, black, grey, white
    public var id: String { rawValue }
    public var name: String { rawValue.capitalized }
    public var hex: String {
        switch self {
        case .red: "#BF4B49"
        case .orange: "#CE7C38"
        case .yellow: "#D7B54A"
        case .green: "#527B45"
        case .teal: "#397B7A"
        case .blue: "#2C6196"
        case .violet: "#865B9D"
        case .pink: "#C38AAB"
        case .brown: "#78503A"
        case .cream: "#EEE1BF"
        case .black: "#202326"
        case .grey: "#8C9296"
        case .white: "#F0EFEB"
        }
    }
    public var isNeutral: Bool { [.cream, .black, .grey, .white].contains(self) }

    static func classify(_ colour: ColourMatch.Lab) -> Self {
        let chroma = hypot(colour.a, colour.b)
        if colour.l < 0.20 || (colour.l < 0.30 && chroma < 0.045) { return .black }
        var hue = atan2(colour.b, colour.a) * 180 / .pi
        if hue < 0 { hue += 360 }
        if colour.l > 0.84 && chroma < 0.075 && (65...110).contains(hue) && chroma >= 0.025 { return .cream }
        if chroma < 0.028 { return colour.l > 0.87 ? .white : .grey }
        if (40...105).contains(hue) && colour.l < 0.64 { return .brown }
        switch hue {
        case 15..<42: return .red
        case 42..<75: return .orange
        case 75..<115: return .yellow
        case 115..<165: return .green
        case 165..<220: return .teal
        case 220..<280: return .blue
        case 280..<328: return .violet
        default: return .pink
        }
    }
}

public enum ColourSelectionStrength: String, Codable, CaseIterable, Sendable {
    case strong, strongAndAccents = "strong_and_accents"
    public var minimumCoverage: Double { self == .strong ? 0.18 : 0.04 }
    public var name: String { self == .strong ? "Strong colours" : "Include accents" }
}
public enum ImageColourStrength: String, Codable, Sendable { case strong, weak }

public struct ImageColourCoverage: Codable, Equatable, Sendable, Identifiable {
    public var family: ColourFamily
    public var coverage: Double
    public var strength: ImageColourStrength
    public var id: ColourFamily { family }
    public init(family: ColourFamily, coverage: Double) {
        self.family = family; self.coverage = coverage; strength = coverage >= 0.18 ? .strong : .weak
    }
}

/// Measured fractions of a small sRGB pixel sample, not guessed palette weights.
public struct ImageColourProfile: Codable, Equatable, Sendable {
    public var version = 1
    public var sampleCount: Int
    public var colours: [ImageColourCoverage]
    public init(coverages: [ColourFamily: Double], sampleCount: Int = 4096) {
        self.sampleCount = sampleCount
        colours = ColourFamily.allCases.compactMap { family in
            guard let value = coverages[family], value > 0 else { return nil }
            return ImageColourCoverage(family: family, coverage: value)
        }
    }
    public func coverage(_ family: ColourFamily) -> Double { colours.first { $0.family == family }?.coverage ?? 0 }
    public func validate() throws {
        guard version == 1, (0...4096).contains(sampleCount), colours.count <= ColourFamily.allCases.count,
              Set(colours.map(\.family)).count == colours.count,
              colours.allSatisfy({ $0.coverage.isFinite && $0.coverage > 0 && $0.coverage <= 1 && $0.strength == ($0.coverage >= 0.18 ? .strong : .weak) }),
              sampleCount == 0 ? colours.isEmpty : abs(colours.reduce(0) { $0 + $1.coverage } - 1) < 0.000001 else {
            throw CorkError("Invalid measured image colour classification.")
        }
    }
    public func weights(for pair: [ColourFamily]) -> [Double] { pair.map(coverage) }
    public func matches(_ pair: [ColourFamily], strength: ColourSelectionStrength) -> Bool {
        guard pair.count == 2, pair.contains(where: { coverage($0) >= strength.minimumCoverage }) else { return false }
        let selected = colours.filter { pair.contains($0.family) && !$0.family.isNeutral }.reduce(0) { $0 + $1.coverage }
        let foreign = colours.filter { !pair.contains($0.family) && !$0.family.isNeutral }.reduce(0) { $0 + $1.coverage }
        // A large white margin must not excuse a different, strongly coloured subject.
        return foreign <= (pair.allSatisfy(\.isNeutral) ? 0.06 : max(0.08, selected * 0.8))
    }
    public var dominantFamily: ColourFamily? { colours.max { $0.coverage < $1.coverage }?.family }
}

extension PaletteAnalysis {
    public static func profile(image: CGImage) throws -> ImageColourProfile {
        let size = 64
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data else {
            throw CorkError("Could not classify image colours.")
        }
        context.interpolationQuality = .medium; context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var counts: [ColourFamily: Int] = [:], samples = 0
        for offset in stride(from: 0, to: size * size * 4, by: 4) where bytes[offset + 3] >= 200 {
            let alpha = Double(bytes[offset + 3])
            let colour = ColourMatch.lab(red: Double(bytes[offset]) / alpha, green: Double(bytes[offset + 1]) / alpha, blue: Double(bytes[offset + 2]) / alpha)
            counts[ColourFamily.classify(colour), default: 0] += 1; samples += 1
        }
        let result = ImageColourProfile(coverages: counts.mapValues { Double($0) / Double(max(1, samples)) }, sampleCount: samples)
        try result.validate(); return result
    }
}
