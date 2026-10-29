import Foundation
import CoreGraphics
import ImageIO

public enum PaletteAnalysis {
    /// Small, deterministic weighted clusters from a colour-managed sRGB thumbnail.
    /// Nothing is uploaded; analysis has bounded pixels and iterations.
    public static func colours(image: CGImage) throws -> [String] {
        let size = 64
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let data = context.data else {
            throw CorkError("Could not analyse image colours.")
        }
        context.interpolationQuality = .medium; context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        struct Sample { var r: Double, g: Double, b: Double, weight: Double }
        var bins: [Int: Sample] = [:]
        for offset in stride(from: 0, to: size * size * 4, by: 4) where bytes[offset + 3] >= 200 {
            let r = Double(bytes[offset]), g = Double(bytes[offset + 1]), b = Double(bytes[offset + 2])
            let key = (Int(r) / 16) << 8 | (Int(g) / 16) << 4 | Int(b) / 16
            if var value = bins[key] { value.r += r; value.g += g; value.b += b; value.weight += 1; bins[key] = value }
            else { bins[key] = Sample(r: r, g: g, b: b, weight: 1) }
        }
        let samples = bins.sorted { $0.key < $1.key }.map { _, v in Sample(r: v.r / v.weight, g: v.g / v.weight, b: v.b / v.weight, weight: v.weight) }
        guard let first = samples.max(by: { $0.weight < $1.weight }) else { return ["#FFFFFF"] }
        func distance(_ a: Sample, _ b: Sample) -> Double { pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2) }
        var centers = [first]
        while centers.count < min(5, samples.count) {
            guard let next = samples.max(by: { a, b in
                (centers.map { distance(a, $0) }.min() ?? 0) * sqrt(a.weight) < (centers.map { distance(b, $0) }.min() ?? 0) * sqrt(b.weight)
            }), (centers.map { distance(next, $0) }.min() ?? 0) > 200 else { break }
            centers.append(next)
        }
        for _ in 0..<8 {
            var sums = centers.map { _ in Sample(r: 0, g: 0, b: 0, weight: 0) }
            for sample in samples {
                guard let index = centers.indices.min(by: { distance(sample, centers[$0]) < distance(sample, centers[$1]) }) else { continue }
                sums[index].r += sample.r * sample.weight; sums[index].g += sample.g * sample.weight
                sums[index].b += sample.b * sample.weight; sums[index].weight += sample.weight
            }
            for index in centers.indices where sums[index].weight > 0 {
                let sum = sums[index]
                centers[index] = Sample(r: sum.r / sum.weight, g: sum.g / sum.weight, b: sum.b / sum.weight, weight: sum.weight)
            }
        }
        return centers.sorted { $0.weight > $1.weight }.map {
            String(format: "#%02X%02X%02X", Int($0.r.rounded()), Int($0.g.rounded()), Int($0.b.rounded()))
        }
    }
}

extension BoardRepository {
    public func imageColours(assetFile: String) throws -> [String] {
        guard assetFile == URL(fileURLWithPath: assetFile).lastPathComponent, !assetFile.hasPrefix(".") else { throw CorkError("Invalid image asset.") }
        guard let source = CGImageSourceCreateWithURL(assets.appendingPathComponent(assetFile) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary) else { throw CorkError("Could not read image colours.") }
        return try PaletteAnalysis.colours(image: image)
    }
}
